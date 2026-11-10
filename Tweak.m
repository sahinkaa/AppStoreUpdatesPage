#import <UIKit/UIKit.h>

static UIViewController *visibleController(UIWindowScene *scene) {
    UIViewController *controller = scene.keyWindow.rootViewController;
    while (controller) {
        UIViewController *next = controller.presentedViewController;
        if (!next && [controller isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)controller).visibleViewController;
        }
        if (!next && [controller isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)controller).selectedViewController;
        }
        if (!next || next == controller || next.isBeingDismissed) break;
        controller = next;
    }
    return controller;
}

static UIRefreshControl *findRefreshControl(UIView *view) {
    if (!view || view.hidden || view.alpha == 0 || !view.window) return nil;
    if ([view isKindOfClass:UIScrollView.class]) {
        UIRefreshControl *control = ((UIScrollView *)view).refreshControl;
        if (control.enabled && (control.allControlEvents & UIControlEventValueChanged)) {
            return control;
        }
    }
    for (UIView *child in view.subviews) {
        UIRefreshControl *control = findRefreshControl(child);
        if (control) return control;
    }
    return nil;
}

static BOOL isUpdatesPage(UIViewController *controller) {
    NSString *className = NSStringFromClass(controller.class);
    for (NSString *name in @[@"AccountViewController", @"AccountCollectionViewController",
                             @"UpdatesViewController", @"AppUpdatesViewController"]) {
        if ([className isEqualToString:name] || [className hasSuffix:[@"." stringByAppendingString:name]]) {
            return YES;
        }
    }

    NSString *title = controller.navigationItem.title ?: controller.title;
    if (!title.length) return NO;
    for (NSString *key in @[@"Account", @"Updates", @"App Updates"]) {
        NSString *localized = [[NSBundle mainBundle] localizedStringForKey:key value:key table:nil];
        if ([title isEqualToString:key] || [title isEqualToString:localized]) return YES;
    }
    return NO;
}

@interface ASUPSession : NSObject
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic, weak) UIViewController *knownUpdatesPage;
@property (nonatomic) BOOL handledActivation;
@property (nonatomic) NSUInteger generation;
- (void)activate;
- (void)background;
@end

@implementation ASUPSession

- (void)background {
    self.handledActivation = NO;
    self.generation++;
}

- (void)activate {
    if (self.handledActivation) return;
    self.handledActivation = YES;
    [self openWhenReady:self.generation attempts:25];
}

- (void)openWhenReady:(NSUInteger)generation attempts:(NSUInteger)attempts {
    UIWindowScene *scene = self.scene;
    if (!scene || generation != self.generation || !attempts) return;

    UIViewController *current = visibleController(scene);
    if (scene.activationState != UISceneActivationStateForegroundActive ||
        !current.viewIfLoaded.window || current.isBeingPresented || current.transitionCoordinator) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self openWhenReady:generation attempts:attempts - 1];
        });
        return;
    }

    if (current == self.knownUpdatesPage || isUpdatesPage(current)) {
        [self refreshWhenReady:generation attempts:30];
        return;
    }

    NSURL *url = [NSURL URLWithString:@"itms-apps://apps.apple.com/updates"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL opened) {
        if (opened) [self refreshWhenReady:generation attempts:30];
    }];
}

- (void)refreshWhenReady:(NSUInteger)generation attempts:(NSUInteger)attempts {
    UIWindowScene *scene = self.scene;
    if (!scene || generation != self.generation || !attempts) return;

    UIViewController *current = visibleController(scene);
    BOOL onUpdatesPage = current && (current == self.knownUpdatesPage || isUpdatesPage(current));
    if (onUpdatesPage) self.knownUpdatesPage = current;

    if (scene.activationState == UISceneActivationStateForegroundActive &&
        onUpdatesPage && current.viewIfLoaded.window && !current.isBeingPresented && !current.transitionCoordinator) {
        UIRefreshControl *refresh = findRefreshControl(current.viewIfLoaded);
        if (refresh) {
            if (!refresh.isRefreshing) {
                [refresh beginRefreshing];
                [refresh sendActionsForControlEvents:UIControlEventValueChanged];
            }
            return;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self refreshWhenReady:generation attempts:attempts - 1];
    });
}

@end

__attribute__((constructor)) static void startUpdatesPage(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.AppStore"]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        NSMapTable<UIWindowScene *, ASUPSession *> *sessions = [NSMapTable weakToStrongObjectsMapTable];
        void (^activate)(UIWindowScene *) = ^(UIWindowScene *scene) {
            ASUPSession *session = [sessions objectForKey:scene];
            if (!session) {
                session = [ASUPSession new];
                session.scene = scene;
                [sessions setObject:session forKey:scene];
            }
            [session activate];
        };
        [center addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIWindowScene.class]) activate(note.object);
        }];
        [center addObserverForName:UISceneDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *note) {
            [[sessions objectForKey:note.object] background];
        }];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                activate((UIWindowScene *)scene);
            }
        }
    });
}

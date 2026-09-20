//
//  Tweak.m —— Minis 通用 iOS 注入 dylib
//  功能：1) 按类名隐藏界面控件（配置驱动）
//        2) 悬浮探针 "探"：点一下列出当前界面所有视图类名，便于定位要删的控件
//  目标：iOS 15+ 运行，arm64；不依赖 Theos，纯 Objective-C + Runtime
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 1. 配置区（只改这里） ====================

// 想隐藏的控件类名。末尾带 * 表示前缀匹配，例：@"Ad_*"
static NSArray<NSString *> *kHideRules(void) {
    static NSArray *rules = nil;
    if (!rules) {
        rules = @[
            // @"UITabBar",
            // @"UINavigationBar",
        ];
    }
    return rules;
}

static BOOL kEnableProbe = YES;   // 显示悬浮探针
static BOOL kVerboseLog  = YES;   // 打印日志

// ==================== 2. 基础设施 ====================

#define MT_LOG(fmt, ...) \
    do { if (kVerboseLog) NSLog(@"[MinTweak] " fmt, ##__VA_ARGS__); } while (0)

static BOOL MTRuleMatches(NSString *cls) {
    if (!cls) return NO;
    for (NSString *rule in kHideRules()) {
        if (rule.length == 0) continue;
        if ([rule hasSuffix:@"*"]) {
            if ([cls hasPrefix:[rule substringToIndex:rule.length - 1]]) return YES;
        } else if ([cls isEqualToString:rule]) {
            return YES;
        }
    }
    return NO;
}

static void MTSwizzleInstance(Class cls, SEL orig, SEL alt) {
    Method m1 = class_getInstanceMethod(cls, orig);
    Method m2 = class_getInstanceMethod(cls, alt);
    if (!m1 || !m2) { MT_LOG(@"swizzle skipped: %@ %@", cls, NSStringFromSelector(orig)); return; }
    if (class_addMethod(cls, orig, method_getImplementation(m2), method_getTypeEncoding(m2))) {
        class_replaceMethod(cls, alt, method_getImplementation(m1), method_getTypeEncoding(m1));
    } else {
        method_exchangeImplementations(m1, m2);
    }
}

// ==================== 3. 按规则隐藏控件 ====================

static void MTApplyHideRules(UIView *v) {
    if (!v) return;
    @try {
        if (MTRuleMatches(NSStringFromClass(v.class))) {
            v.hidden = YES;
            v.alpha = 0.0;
            v.userInteractionEnabled = NO;
            MT_LOG(@"hidden: %@ %@", NSStringFromClass(v.class), NSStringFromCGRect(v.frame));
        }
    } @catch (NSException *e) { }
}

@interface UIView (MinTweakHide)
- (void)mt_didMoveToWindow;
@end

@implementation UIView (MinTweakHide)
- (void)mt_didMoveToWindow {
    [self mt_didMoveToWindow];
    MTApplyHideRules(self);
}
@end

// ==================== 4. 悬浮探针 ====================

@interface MTPassthroughView : UIView @end
@implementation MTPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;   // 空白区域不拦截触摸，不影响原 App
}
@end

static NSString *MTDescribeView(UIView *v, int depth) {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < depth; i++) [s appendString:@"  "];
    [s appendFormat:@"%@  %@  tag=%ld%@%@",
        NSStringFromClass(v.class), NSStringFromCGRect(v.frame), (long)v.tag,
        v.hidden ? @"  [hidden]" : @"",
        (v.alpha < 1.0) ? @"  [alpha<1]" : @""];
    if ([v isKindOfClass:UILabel.class] && [(UILabel *)v text].length)
        [s appendFormat:@"  text=%@", [(UILabel *)v text]];
    else if ([v isKindOfClass:UIButton.class] &&
             [[(UIButton *)v titleForState:UIControlStateNormal] length])
        [s appendFormat:@"  title=%@", [(UIButton *)v titleForState:UIControlStateNormal]];
    else if ([v isKindOfClass:UIImageView.class] && [(UIImageView *)v image])
        [s appendString:@"  [image]"];
    [s appendString:@"\n"];
    for (UIView *sub in v.subviews) [s appendString:MTDescribeView(sub, depth + 1)];
    return s;
}

static UIWindow *gProbeWindow = nil;
static UIView   *gBall   = nil;
static UIView   *gPanel  = nil;
static UITextView *gText = nil;

@interface MTProbe : NSObject
+ (instancetype)shared;
- (void)install;
- (void)showPanel;
- (void)hidePanel;
- (void)handlePan:(UIPanGestureRecognizer *)g;
- (void)handleTap;
- (void)handleLongPress;
@end

static NSArray<UIWindow *> *MTAllWindows(void) {
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class])
            [out addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    return out;
}

static UIWindow *MTKeyWindow(void) {
    NSArray<UIWindow *> *all = MTAllWindows();
    for (UIWindow *w in all) if (w.isKeyWindow) return w;
    return all.firstObject;
}

static UIWindow *MTProbeWindow(void) {
    if (gProbeWindow) return gProbeWindow;
    UIWindow *host = MTKeyWindow();
    if (!host) return nil;

    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        if (host.windowScene) win = [[UIWindow alloc] initWithWindowScene:host.windowScene];
    }
    if (!win) win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.windowLevel = UIWindowLevelAlert + 100;
    win.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view = [[MTPassthroughView alloc] initWithFrame:win.bounds];
    vc.view.backgroundColor = UIColor.clearColor;
    win.rootViewController = vc;
    win.hidden = NO;
    gProbeWindow = win;
    return win;
}

@implementation MTProbe

+ (instancetype)shared {
    static MTProbe *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MTProbe new]; });
    return s;
}

- (void)install {
    if (gBall) return;
    UIWindow *win = MTProbeWindow();
    if (!win) {
        static int retry = 0;
        if (retry++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self install]; });
        }
        return;
    }
    UIView *host = win.rootViewController.view;

    UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(10, 140, 46, 46)];
    ball.backgroundColor = [UIColor colorWithRed:0.10 green:0.48 blue:0.92 alpha:0.85];
    ball.layer.cornerRadius = 23;
    ball.layer.shadowColor = UIColor.blackColor.CGColor;
    ball.layer.shadowOpacity = 0.3;
    ball.layer.shadowRadius = 4;
    ball.layer.shadowOffset = CGSizeMake(0, 2);

    UILabel *lbl = [[UILabel alloc] initWithFrame:ball.bounds];
    lbl.text = @"探";
    lbl.textColor = UIColor.whiteColor;
    lbl.font = [UIFont boldSystemFontOfSize:18];
    lbl.textAlignment = NSTextAlignmentCenter;
    [ball addSubview:lbl];

    [ball addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleTap)]];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress)];
    [ball addGestureRecognizer:lp];
    [ball addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)]];

    [host addSubview:ball];
    gBall = ball;
    MT_LOG(@"探针已就位");
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    UIView *ball = g.view;
    UIView *host = ball.superview;
    CGPoint t = [g translationInView:host];
    CGPoint c = CGPointMake(ball.center.x + t.x, ball.center.y + t.y);
    c.x = MAX(23, MIN(host.bounds.size.width - 23, c.x));
    c.y = MAX(23, MIN(host.bounds.size.height - 23, c.y));
    ball.center = c;
    [g setTranslation:CGPointZero inView:host];
}

- (void)handleLongPress {
    gBall.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ gBall.hidden = NO; });
}

- (void)handleTap {
    if (gPanel) [self hidePanel]; else [self showPanel];
}

- (void)showPanel {
    UIWindow *win = MTProbeWindow();
    if (!win) return;
    UIView *host = win.rootViewController.view;

    UIWindow *key = nil;
    for (UIWindow *w in MTAllWindows()) {
        if (w != gProbeWindow && w.isKeyWindow) { key = w; break; }
    }
    UIView *target = key ?: host;

    NSString *dump = [NSString stringWithFormat:@"window: %@\n\n%@",
        NSStringFromCGRect(target.bounds), MTDescribeView(target, 0)];

    CGRect f = host.bounds;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectInset(f, 8, 60)];
    panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
    panel.layer.cornerRadius = 12;
    panel.clipsToBounds = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, panel.bounds.size.width - 24, 20)];
    title.text = @"视图树（点右上角 × 关闭）";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:title];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(8, 34,
                        panel.bounds.size.width - 16, panel.bounds.size.height - 42)];
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = [UIColor colorWithRed:0.6 green:1.0 blue:0.7 alpha:1.0];
    tv.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    tv.editable = NO;
    tv.text = dump;
    [panel addSubview:tv];
    gText = tv;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(panel.bounds.size.width - 44, 4, 40, 30);
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [close addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    [host addSubview:panel];
    gPanel = panel;

    MT_LOG(@"\n%@", dump);
}

- (void)hidePanel {
    [gPanel removeFromSuperview];
    gPanel = nil;
    gText = nil;
}

@end

// ==================== 5. 入口 ====================

@interface UIViewController (MinTweakProbe)
- (void)mt_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (MinTweakProbe)
- (void)mt_viewDidAppear:(BOOL)animated {
    [self mt_viewDidAppear:animated];
    if (kEnableProbe) [[MTProbe shared] install];
}
@end

__attribute__((constructor))
static void MinTweakInit(void) {
    @autoreleasepool {
        MT_LOG(@"loaded in %@ (%s)", NSBundle.mainBundle.bundleIdentifier,
               NSBundle.mainBundle.bundleIdentifier.UTF8String);

        // 隐藏规则
        MTSwizzleInstance(UIView.class,
                          @selector(didMoveToWindow),
                          @selector(mt_didMoveToWindow));

        // 探针
        if (kEnableProbe) {
            MTSwizzleInstance(UIViewController.class,
                              @selector(viewDidAppear:),
                              @selector(mt_viewDidAppear:));
        }

        MT_LOG(@"hide rules = %@", kHideRules());
    }
}

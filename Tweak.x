// AutoHideKeyboard - 微信发送消息后自动收起键盘 v2.0
// Theos/Logos tweak · 参考 AutoHideKeyboard.dylib 逆向重建
// v2.0: 界面重制（内缩分组样式、滑杆调延迟、测试行、版本信息）
// 目标: iOS 微信 (com.tencent.xin)

#import <UIKit/UIKit.h>
#import <objc/message.h>

// ---------- 配置键 ----------
static NSString * const kPrefEnabled  = @"AutoHideKeyboardEnabled";
static NSString * const kPrefDelay    = @"AutoHideKeyboardDelay";
static NSString * const kPrefSendOnly = @"AutoHideKeyboardSendOnly";

static NSString * const kAHKVersion = @"2.1";

// ---------- 配置读取 ----------
static BOOL AHKEnabled(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefEnabled];
    return v ? [v boolValue] : YES; // 默认开启
}

static BOOL AHKSendOnly(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefSendOnly];
    return v ? [v boolValue] : NO;
}

static NSTimeInterval AHKDelay(void) {
    double d = [[NSUserDefaults standardUserDefaults] doubleForKey:kPrefDelay];
    return d > 0 ? d : 0.2; // 默认 0.2 秒
}

#define AHKLog(fmt, ...) do {} while (0)

// ---------- 核心状态 ----------
static NSInteger AHKGen = 0;      // 活动代数: 新活动使挂起的收起失效
static BOOL AHKKeyboardSeen = NO; // 本次启动是否跟踪到过输入框

static UITextView *AHKFindEditingTextView(UIResponder *fr) {
    if ([fr isKindOfClass:%c(UITextView)]) return (UITextView *)fr;
    return nil;
}

static void AHKHideKeyboardNow(void) {
    if (!AHKEnabled()) { AHKLog(@"skip hide: disabled by user"); return; }

    UIWindow *window = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    if (!window) { AHKLog(@"skip hide: no key window"); return; }

    UIResponder *fr = nil;
    if ([window respondsToSelector:@selector(firstResponder)]) {
        fr = [window performSelector:@selector(firstResponder)];
    }
    BOOL editing = [fr isKindOfClass:%c(UITextView)] || [fr isKindOfClass:%c(UITextField)]
                   || (fr && [fr conformsToProtocol:@protocol(UIKeyInput)]);
    if (!editing) { AHKLog(@"skip hide: no first responder"); return; }

    // 与原版一致的细节: 正在拼音组词不收, 输入框还有内容不收
    UITextView *tv = AHKFindEditingTextView(fr);
    if (tv) {
        if (tv.markedTextRange) { AHKLog(@"skip hide: composing (markedTextRange) → 不收"); return; }
        if (tv.text.length > 0) { AHKLog(@"skip hide: 输入框有内容（%lu 字）→ 不收", (unsigned long)tv.text.length); return; }
    }

    [window endEditing:YES];
    AHKKeyboardSeen = NO;
    AHKLog(@"keyboard hidden (view=%@)", window);
}

// 输入/触摸活动: 取消挂起的收起; 非仅发送模式下重新安排闲置收起
static void AHKNoteActivity(void) {
    AHKGen++;
    if (!AHKSendOnly() && AHKEnabled() && AHKKeyboardSeen) {
        NSInteger g = AHKGen;
        NSTimeInterval d = AHKDelay();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (g == AHKGen) {
                // 闲置模式: 仅输入框为空时收起
                UIWindow *window = nil;
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
                if (!window) return;
                UITextView *tv = nil;
                if ([window respondsToSelector:@selector(firstResponder)]) {
                    tv = AHKFindEditingTextView([window performSelector:@selector(firstResponder)]);
                }
                if (tv && tv.text.length == 0) {
                    AHKLog(@"idle %.2fs reached 且输入框为空 → hide keyboard", d);
                    [window endEditing:YES];
                    AHKKeyboardSeen = NO;
                }
            }
        });
    }
}

// 发送消息后调用: 延迟收起键盘(不受 SendOnly 限制)
static void AHKAfterSend(void) {
    if (!AHKEnabled()) return;
    NSInteger g = ++AHKGen;
    NSTimeInterval d = AHKDelay();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (g == AHKGen) AHKHideKeyboardNow();
    });
}

// ==================== 设置页 (v2 界面) ====================
@interface AHKSettingsViewController : UITableViewController <UITextFieldDelegate>
@end

@implementation AHKSettingsViewController {
    UILabel *_delayValueLabel;
    UISlider *_delaySlider;
    UIView *_delayAccessory;
}

- (instancetype)init {
    // 微信插件列表通过类名实例化(可能调用 plain init), 统一走内缩分组样式
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"自动收起键盘";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(doneTapped)];
}

- (void)doneTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ---------- 延迟滑杆行 ----------
- (UIView *)delayAccessoryView {
    if (!_delaySlider) {
        _delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
        _delaySlider.minimumValue = 0.0;
        _delaySlider.maximumValue = 3.0;
        _delaySlider.value = (float)AHKDelay();
        [_delaySlider addTarget:self action:@selector(delayChanged:)
                 forControlEvents:UIControlEventValueChanged];

        _delayValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(148, 0, 84, 30)];
        _delayValueLabel.textAlignment = NSTextAlignmentRight;
        _delayValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        _delayValueLabel.text = [NSString stringWithFormat:@"%.2f 秒", AHKDelay()];
        if (@available(iOS 13.0, *)) {
            _delayValueLabel.textColor = [UIColor secondaryLabelColor];
        }

        _delayAccessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 232, 30)];
        [_delayAccessory addSubview:_delaySlider];
        [_delayAccessory addSubview:_delayValueLabel];
    }
    return _delayAccessory;
}

- (void)delayChanged:(UISlider *)slider {
    double d = round(slider.value * 50.0) / 50.0; // 0.02s 步进
    if (d < 0.05) d = 0.05;
    [[NSUserDefaults standardUserDefaults] setDouble:d forKey:kPrefDelay];
    [[NSUserDefaults standardUserDefaults] synchronize];
    _delayValueLabel.text = [NSString stringWithFormat:@"%.2f 秒", d];
}

// ---------- 表格 ----------
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"行为设置";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"发送文字消息后，延迟指定时间自动收起键盘。\n"
           @"开启「仅发送后收起」时不再进行闲置检测；关闭时，输入闲置且输入框为空也会自动收起。\n"
           @"正在打拼音或输入框有草稿时不会误收。\n\n"
           [NSString stringWithFormat:@"AutoHideKeyboard v%@ · 仅 Hook 微信文字发送与键盘行为，不联网、不读取聊天记录", kAHKVersion];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AHKCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:@"AHKCell"];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;

    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: { // 启用
                cell.textLabel.text = @"启用";
                UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
                sw.on = AHKEnabled();
                [sw addTarget:self action:@selector(enabledChanged:)
                   forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                break;
            }
            case 1: { // 仅发送后收起
                cell.textLabel.text = @"仅发送后收起";
                UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
                sw.on = AHKSendOnly();
                [sw addTarget:self action:@selector(sendOnlyChanged:)
                   forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                break;
            }
            case 2: { // 延迟滑杆
                cell.textLabel.text = @"收起延迟";
                cell.accessoryView = [self delayAccessoryView];
                break;
            }
            case 3: { // 测试
                cell.textLabel.text = @"立即测试收起";
                cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
            }
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3) {
        [self runHideTest];
    }
}

// 立即测试收起: 收掉当前键盘并给出可见反馈
- (void)runHideTest {
    AHKGen++;
    UIWindow *window = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    BOOL keyboardUp = NO;
    if (window) {
        UIResponder *fr = nil;
        if ([window respondsToSelector:@selector(firstResponder)]) {
            fr = [window performSelector:@selector(firstResponder)];
        }
        keyboardUp = fr && ([fr isKindOfClass:[UITextView class]] || [fr isKindOfClass:[UITextField class]]
                            || [fr conformsToProtocol:@protocol(UIKeyInput)]);
        [window endEditing:YES];
    }
    NSString *msg = keyboardUp
        ? @"已收起键盘 ✓"
        : @"当前没有弹出的键盘。\n去聊天页发送一条消息，会按延迟时间自动收起。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enabledChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kPrefEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)sendOnlyChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kPrefSendOnly];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// ==================== Hook: 输入焦点跟踪 ====================
%hook UITextView

- (BOOL)becomeFirstResponder {
    BOOL r = %orig;
    if (r) { AHKKeyboardSeen = YES; AHKNoteActivity(); }
    return r;
}

- (void)setText:(NSString *)text {
    %orig;
    if (self.isFirstResponder) AHKNoteActivity();
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    if (self.isFirstResponder) AHKNoteActivity();
}

- (void)insertText:(NSString *)text {
    %orig;
    AHKNoteActivity();
}

- (void)deleteBackward {
    %orig;
    AHKNoteActivity();
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    %orig;
    AHKNoteActivity();
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    %orig;
    AHKNoteActivity();
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (newWindow == nil) AHKKeyboardSeen = NO;
}

%end

%hook UITextField

- (BOOL)becomeFirstResponder {
    BOOL r = %orig;
    if (r) { AHKKeyboardSeen = YES; AHKNoteActivity(); }
    return r;
}

%end

// ==================== Hook: 全局触摸(闲置模式用) ====================
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (!AHKSendOnly() && event.type == UIEventTypeTouches && AHKKeyboardSeen) {
        AHKNoteActivity();
    }
}

%end

// ==================== Hook: 微信发送消息 ====================
// 覆盖所有聊天类型(与参考 dylib 一致):
//   BaseMsgContentLogicController / WeixinContentLogicController /
//   EnterpriseMsgContentLogicController / MassSendContentLogicController /
//   RoomContentLogicController

%hook BaseMsgContentLogicController
- (void)SendTextMessage:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 externInfo:(id)arg2 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessageWithSolitaire:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 replyingMessage:(id)arg2 isPasted:(BOOL)arg3 {
    %orig;
    AHKAfterSend();
}
%end

%hook WeixinContentLogicController
- (void)SendTextMessage:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 externInfo:(id)arg2 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessageWithSolitaire:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 replyingMessage:(id)arg2 isPasted:(BOOL)arg3 {
    %orig;
    AHKAfterSend();
}
%end

%hook EnterpriseMsgContentLogicController
- (void)SendTextMessage:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 externInfo:(id)arg2 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessageWithSolitaire:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 replyingMessage:(id)arg2 isPasted:(BOOL)arg3 {
    %orig;
    AHKAfterSend();
}
%end

%hook MassSendContentLogicController
- (void)SendTextMessage:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 externInfo:(id)arg2 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessageWithSolitaire:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 replyingMessage:(id)arg2 isPasted:(BOOL)arg3 {
    %orig;
    AHKAfterSend();
}
%end

%hook RoomContentLogicController
- (void)SendTextMessage:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 externInfo:(id)arg2 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessageWithSolitaire:(id)arg1 {
    %orig;
    AHKAfterSend();
}
- (void)SendTextMessage:(id)arg1 replyingMessage:(id)arg2 isPasted:(BOOL)arg3 {
    %orig;
    AHKAfterSend();
}
%end

// ==================== Hook: 微信设置页入口 ====================
// 在微信"我-设置"列表末尾加一行入口(类名随微信版本可能变化, 不存在时自动跳过)
static NSInteger AHKOrigSettingCount = -1;
static void AHKRegisterToWCPlugins(void);
static void AHKRegisterOnActive(void);

%hook NewSettingViewController

- (void)viewDidLoad {
    %orig;
    // 打开设置页时兜底重试注册(此时登录态一定有效)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ AHKRegisterOnActive(); });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger n = %orig;
    if (section == 0) {
        AHKOrigSettingCount = n;
        n += 1;
    }
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && AHKOrigSettingCount >= 0 && indexPath.row == AHKOrigSettingCount) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AHKEntry"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:@"AHKEntry"];
        }
        cell.textLabel.text = @"自动收起键盘";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && AHKOrigSettingCount >= 0 && indexPath.row == AHKOrigSettingCount) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        AHKSettingsViewController *vc = [[AHKSettingsViewController alloc]
            initWithStyle:UITableViewStyleInsetGrouped];
        UIViewController *selfVC = (UIViewController *)self;
        UINavigationController *nav = selfVC.navigationController;
        if (nav) [nav pushViewController:vc animated:YES];
        else [selfVC presentViewController:vc animated:YES completion:nil];
        return;
    }
    %orig;
}

%end

// ==================== 插件收纳注册入口（与原版一致） ====================
// 通过微信内部插件管理器 WCPluginsMgr 注册设置页，出现在微信的"插件收纳"列表中。
// 注册依赖登录态（插件列表按账号刷新），因此：启动时重试 + 每次微信激活时重试 +
// 打开设置页时兜底重试；已注册则跳过（微信内部按 title 作 key，重复注册是覆盖不是新增）。

static BOOL gAHKRegistered = NO;
static NSInteger gAHKActiveRetry = 0;

static id AHKPluginsMgr(void) {
    Class mgrClass = %c(WCPluginsMgr);
    if (!mgrClass) return nil;

    // 优先 sharedInstance: 第三方"插件收纳"兼容层(懒猫等)通常挂在这个入口
    if ([mgrClass respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(mgrClass, @selector(sharedInstance));
        if (mgr) return mgr;
    }
    // 兜底: 微信标准服务总线 MMServiceCenter
    Class scClass = %c(MMServiceCenter);
    if (scClass && [scClass respondsToSelector:@selector(defaultCenter)]) {
        id center = ((id (*)(id, SEL))objc_msgSend)(scClass, @selector(defaultCenter));
        if (center && [center respondsToSelector:@selector(getService:)]) {
            return ((id (*)(id, SEL, id))objc_msgSend)(center, @selector(getService:), mgrClass);
        }
    }
    return nil;
}

static void AHKRegisterToWCPlugins(void) {
    if (gAHKRegistered) return;

    @try {
        id mgr = AHKPluginsMgr();
        if (!mgr) { AHKLog(@"wcplugins 未就绪，注册放弃"); return; }

        SEL sel = @selector(registerControllerWithTitle:version:controller:);
        if (![mgr respondsToSelector:sel]) {
            AHKLog(@"wcplugins 接口不可用，注册放弃");
            return;
        }

        // 关键: controller 参数是"控制器类名字符串"而非实例, 微信用 NSClassFromString 实例化
        ((void (*)(id, SEL, id, id, id))objc_msgSend)
            (mgr, sel, @"自动收起键盘", kAHKVersion, @"AHKSettingsViewController");

        gAHKRegistered = YES;
        AHKLog(@"已注册到 wcplugins 收纳列表（自动收起键盘 v%@）", kAHKVersion);
    }
    @catch (NSException *e) {
        AHKLog(@"wcplugins 注册异常: %@", e);
    }
}

// 微信每次激活/进入前台都尝试注册(登录完成后必触发), 最多 10 次
static void AHKRegisterOnActive(void) {
    if (gAHKRegistered || gAHKActiveRetry >= 10) return;
    gAHKActiveRetry++;
    AHKRegisterToWCPlugins();
    if (!gAHKRegistered) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ AHKRegisterOnActive(); });
    }
}

%hook WCPluginsMgr

- (id)init {
    id r = %orig;
    // 管理器真正实例化的时机即注册时机（比猜启动延迟可靠得多）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ AHKRegisterToWCPlugins(); });
    return r;
}

%end

%hook MainAppViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AHKRegisterOnActive();
}

%end

%ctor {
    @autoreleasepool {
        // 启动序列重试
        for (NSNumber *num in @[@2.0, @5.0, @10.0, @20.0, @30.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(num.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                AHKRegisterToWCPlugins();
            });
        }
        // 微信进入前台/激活时重试(登录完成后必触发)
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:nil
            usingBlock:^(NSNotification *note) { AHKRegisterOnActive(); }];
    }
}

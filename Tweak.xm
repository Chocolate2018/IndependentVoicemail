#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <dlfcn.h>

#pragma mark ==================================================
#pragma mark Configuration
#pragma mark ==================================================

static NSTimeInterval const IVAnswerDelay = 20.0;

/*
 * 自定义问候语：
 *
 * /var/mobile/Library/Preferences/IndependentVoicemail/
 * Greeting.caf
 *
 * 如果文件不存在，则跳过问候语播放。
 */

static NSString * const IVRootDirectory =
    @"/var/mobile/Library/Preferences/IndependentVoicemail";

static NSString * const IVGreetingPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemail/Greeting.caf";

static NSString * const IVRecordingDirectory =
    @"/var/mobile/Library/Preferences/IndependentVoicemail/Recordings";

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemail/IndependentVoicemail.log";


#pragma mark ==================================================
#pragma mark Global State
#pragma mark ==================================================

static id IVCurrentCall = nil;

static NSTimer *IVAnswerTimer = nil;

static AVAudioPlayer *IVGreetingPlayer = nil;

static AVAudioRecorder *IVRecorder = nil;

static BOOL IVAnswerInProgress = NO;

static BOOL IVCallActive = NO;

static BOOL IVGreetingFinished = NO;

static BOOL IVRecordingStarted = NO;

static BOOL IVAudioPrepared = NO;


#pragma mark ==================================================
#pragma mark Logging
#pragma mark ==================================================

static void IVLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format
                               arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:
            @"[%@] %@\n",
            [NSDate date],
            message];

    NSFileHandle *handle =
        [NSFileHandle fileHandleForWritingAtPath:IVLogPath];

    if (!handle) {

        [[NSFileManager defaultManager]
            createFileAtPath:IVLogPath
            contents:nil
            attributes:nil];

        handle =
            [NSFileHandle fileHandleForWritingAtPath:IVLogPath];
    }

    if (handle) {

        @try {

            [handle seekToEndOfFile];

            NSData *data =
                [line dataUsingEncoding:
                    NSUTF8StringEncoding];

            [handle writeData:data];

            [handle closeFile];

        } @catch (__unused NSException *exception) {

        }
    }
}


#pragma mark ==================================================
#pragma mark Directory
#pragma mark ==================================================

static void IVCreateDirectories(void)
{
    NSFileManager *fm =
        [NSFileManager defaultManager];

    NSError *error = nil;

    [fm createDirectoryAtPath:IVRootDirectory
   withIntermediateDirectories:YES
                    attributes:nil
                         error:&error];

    if (error) {

        IVLog(@"Root directory error: %@",
              error);
    }

    error = nil;

    [fm createDirectoryAtPath:IVRecordingDirectory
   withIntermediateDirectories:YES
                    attributes:nil
                         error:&error];

    if (error) {

        IVLog(@"Recording directory error: %@",
              error);
    }
}


#pragma mark ==================================================
#pragma mark Audio Session
#pragma mark ==================================================

static BOOL IVPrepareAudioSession(void)
{
    /*
     * 这一部分只有在接通以后才执行。
     *
     * 不在 SpringBoard 启动阶段激活 AudioSession。
     */

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSError *error = nil;

    BOOL ok =
        [session setCategory:
                    AVAudioSessionCategoryPlayAndRecord
                   mode:
                    AVAudioSessionModeVoiceChat
                options:
                    AVAudioSessionCategoryOptionAllowBluetooth
                    |
                    AVAudioSessionCategoryOptionDefaultToSpeaker
                  error:&error];

    if (!ok || error) {

        IVLog(@"Audio category failed: %@",
              error);

        return NO;
    }

    error = nil;

    ok =
        [session setActive:YES
                     error:&error];

    if (!ok || error) {

        IVLog(@"Audio session activation failed: %@",
              error);

        return NO;
    }

    IVAudioPrepared = YES;

    IVLog(@"Audio session prepared");

    return YES;
}


#pragma mark ==================================================
#pragma mark Stop Audio
#pragma mark ==================================================


#pragma mark ==================================================
#pragma mark Greeting
#pragma mark ==================================================

static void IVStartRecording(void);

static void IVGreetingDidFinish(void)
{
    IVLog(@"Greeting finished");

    IVGreetingFinished = YES;

    IVGreetingPlayer = nil;

    /*
     * 问候语播放完立即进入录音。
     */

    IVStartRecording();
}


static void IVPlayGreeting(void)
{
    if (!IVCallActive) {

        IVLog(@"Cannot play greeting: call inactive");

        return;
    }

    NSFileManager *fm =
        [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:IVGreetingPath]) {

        IVLog(@"Greeting not found");

        /*
         * 没有自定义问候语时直接录音。
         */

        IVStartRecording();

        return;
    }

    NSError *error = nil;

    NSURL *url =
        [NSURL fileURLWithPath:IVGreetingPath];

    IVGreetingPlayer =
        [[AVAudioPlayer alloc]
            initWithContentsOfURL:url
                            error:&error];

    if (!IVGreetingPlayer || error) {

        IVLog(@"Greeting player failed: %@",
              error);

        IVGreetingPlayer = nil;

        IVStartRecording();

        return;
    }

    IVGreetingPlayer.delegate =
        (id<AVAudioPlayerDelegate>)nil;

    /*
     * 使用通知观察播放结束。
     */

    [[NSNotificationCenter defaultCenter]
        addObserverForName:
            @"IndependentVoicemailGreetingFinished"
        object:nil
         queue:nil
    usingBlock:^(NSNotification *note) {

        IVGreetingDidFinish();
    }];

    /*
     * AVAudioPlayer 本身的 delegate 更可靠，
     * 这里使用内部代理对象困难，因此使用定时器。
     */

    NSTimeInterval duration =
        IVGreetingPlayer.duration;

    BOOL started =
        [IVGreetingPlayer play];

    if (!started) {

        IVLog(@"Greeting playback failed");

        IVGreetingPlayer = nil;

        IVStartRecording();

        return;
    }

    IVLog(@"Greeting started duration=%.2f",
          duration);

    /*
     * 通过 GCD 等待播放结束。
     */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(duration * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{

        if (!IVCallActive)
            return;

        if (IVGreetingPlayer) {

            IVGreetingDidFinish();
        }
    });
}


#pragma mark ==================================================
#pragma mark Recording
#pragma mark ==================================================

static NSString *IVNewRecordingPath(void)
{
    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    [formatter setDateFormat:
        @"yyyy-MM-dd-HH-mm-ss"];

    NSString *date =
        [formatter stringFromDate:[NSDate date]];

    return
        [IVRecordingDirectory
            stringByAppendingPathComponent:
                [NSString stringWithFormat:
                    @"Voicemail-%@.m4a",
                    date]];
}


static void IVStartRecording(void)
{
    if (!IVCallActive) {

        IVLog(@"Recording refused: call inactive");

        return;
    }

    if (IVRecordingStarted) {

        IVLog(@"Recording already started");

        return;
    }

    NSString *path =
        IVNewRecordingPath();

    NSURL *url =
        [NSURL fileURLWithPath:path];

    NSDictionary *settings = @{
        AVFormatIDKey :
            @(kAudioFormatMPEG4AAC),

        AVSampleRateKey :
            @44100,

        AVNumberOfChannelsKey :
            @1,

        AVEncoderAudioQualityKey :
            @(AVAudioQualityHigh)
    };

    NSError *error = nil;

    IVRecorder =
        [[AVAudioRecorder alloc]
            initWithURL:url
            settings:settings
            error:&error];

    if (!IVRecorder || error) {

        IVLog(@"Recorder creation failed: %@",
              error);

        IVRecorder = nil;

        return;
    }

    BOOL prepared =
        [IVRecorder prepareToRecord];

    if (!prepared) {

        IVLog(@"Recorder prepare failed");

        IVRecorder = nil;

        return;
    }

    BOOL started =
        [IVRecorder record];

    if (!started) {

        IVLog(@"Recorder start failed");

        IVRecorder = nil;

        return;
    }

    IVRecordingStarted = YES;

    IVLog(@"Recording started: %@",
          path);
}


#pragma mark ==================================================
#pragma mark Call Cleanup
#pragma mark ==================================================


#pragma mark ==================================================
#pragma mark Runtime
#pragma mark ==================================================

static Class IVGetClass(NSString *name)
{
    if (!name)
        return Nil;

    return objc_getClass(
        [name UTF8String]
    );
}


#pragma mark ==================================================
#pragma mark TUAnswerRequest
#pragma mark ==================================================

static id IVCreateAnswerRequest(void)
{
    Class requestClass =
        IVGetClass(@"TUAnswerRequest");

    if (!requestClass) {

        IVLog(@"TUAnswerRequest unavailable");

        return nil;
    }

    IVLog(@"TUAnswerRequest found");

    /*
     * 优先寻找 +request...
     */

    Class meta =
        object_getClass(requestClass);

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(meta, &count);

    SEL factory = NULL;

    for (unsigned int i = 0;
         i < count;
         i++) {

        SEL selector =
            method_getName(methods[i]);

        const char *name =
            sel_getName(selector);

        if (!name)
            continue;

        unsigned int args =
            method_getNumberOfArguments(methods[i]);

        /*
         * self + _cmd
         */

        if (args != 2)
            continue;

        if (strstr(name, "request") ||
            strstr(name, "Request")) {

            factory = selector;

            break;
        }
    }

    free(methods);

    if (factory) {

        IVLog(@"Using TUAnswerRequest factory: %s",
              sel_getName(factory));

        id (*msg)(id, SEL) =
            (id (*)(id, SEL))objc_msgSend;

        id request =
            msg(requestClass, factory);

        if (request) {

            IVLog(@"TUAnswerRequest created");

            return request;
        }
    }

    /*
     * 最后尝试普通 init。
     *
     * 只有零参数 init。
     */

    SEL initSelector =
        @selector(init);

    if ([requestClass instancesRespondToSelector:initSelector]) {

        id (*allocMsg)(id, SEL) =
            (id (*)(id, SEL))objc_msgSend;

        id object =
            allocMsg(requestClass,
                     @selector(alloc));

        if (object) {

            id (*initMsg)(id, SEL) =
                (id (*)(id, SEL))objc_msgSend;

            id request =
                initMsg(object,
                        initSelector);

            if (request) {

                IVLog(@"TUAnswerRequest created using init");

                return request;
            }
        }
    }

    IVLog(@"Unable to create TUAnswerRequest");

    return nil;
}


#pragma mark ==================================================
#pragma mark Answer Call
#pragma mark ==================================================

static BOOL IVAnswerCall(void)
{
    if (IVAnswerInProgress)
        return NO;

    id call =
        IVCurrentCall;

    if (!call) {

        IVLog(@"Answer failed: no call");

        return NO;
    }

    IVAnswerInProgress = YES;

    IVLog(@"================================");
    IVLog(@"AUTO ANSWER");
    IVLog(@"================================");

    SEL selector =
        NSSelectorFromString(@"answerWithRequest:");

    if (![call respondsToSelector:selector]) {

        IVLog(@"answerWithRequest: unavailable");

        IVAnswerInProgress = NO;

        return NO;
    }

    id request =
        IVCreateAnswerRequest();

    if (!request) {

        IVLog(@"No answer request");

        IVAnswerInProgress = NO;

        return NO;
    }

    void (*answerMsg)(id, SEL, id) =
        (void (*)(id, SEL, id))objc_msgSend;

    @try {

        answerMsg(call,
                  selector,
                  request);

        IVLog(@"answerWithRequest: sent");

    } @catch (NSException *exception) {

        IVLog(@"answer exception: %@",
              exception);

        IVAnswerInProgress = NO;

        return NO;
    }

    IVAnswerInProgress = NO;

    /*
     * 给电话服务一点时间完成接通。
     */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            1200 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

        if (!IVCurrentCall)
            return;

        IVCallActive = YES;

        IVLog(@"Call presumed connected");

        if (IVPrepareAudioSession()) {

            IVPlayGreeting();

        } else {

            IVLog(@"Audio session unavailable");
        }
    });

    return YES;
}


#pragma mark ==================================================
#pragma mark Schedule Answer
#pragma mark ==================================================

static void IVScheduleAnswer(id call)
{
    if (!call)
        return;

    if (IVAnswerTimer) {

        IVLog(@"Answer timer already active");

        return;
    }

    IVCurrentCall = call;

    IVCallActive = NO;

    IVGreetingFinished = NO;

    IVRecordingStarted = NO;

    IVLog(@"Incoming call captured");

    IVLog(@"Auto answer in %.1f seconds",
          IVAnswerDelay);

    IVAnswerTimer =
        [NSTimer scheduledTimerWithTimeInterval:
            IVAnswerDelay
                                         repeats:NO
                                           block:
        ^(NSTimer *timer) {

        IVAnswerTimer = nil;

        if (!IVCurrentCall) {

            IVLog(@"Call disappeared");

            return;
        }

        IVAnswerCall();
    }];
}


#pragma mark ==================================================
#pragma mark Notification
#pragma mark ==================================================

static id IVExtractCall(NSNotification *note)
{
    if (!note)
        return nil;

    id object =
        note.object;

    if (object) {

        Class cls =
            object_getClass(object);

        if (cls) {

            const char *name =
                class_getName(cls);

            if (name &&
                (strcmp(name, "TUProxyCall") == 0 ||
                 strcmp(name, "TUCall") == 0)) {

                return object;
            }
        }
    }

    NSDictionary *info =
        note.userInfo;

    if (!info)
        return nil;

    for (id key in info) {

        id value =
            [info objectForKey:key];

        if (!value)
            continue;

        Class cls =
            object_getClass(value);

        if (!cls)
            continue;

        const char *name =
            class_getName(cls);

        if (name &&
            (strcmp(name, "TUProxyCall") == 0 ||
             strcmp(name, "TUCall") == 0)) {

            return value;
        }
    }

    return nil;
}


static void IVHandleNotification(NSNotification *note)
{
    if (!note)
        return;

    NSString *name =
        note.name;

    if (!name)
        return;

    IVLog(@"Notification: %@",
          name);


    /*
     * Incoming call.
     */

    if ([name isEqualToString:
        @"SBIncomingCallPendingNotification"]) {

        id call =
            IVExtractCall(note);

        if (call) {

            IVScheduleAnswer(call);

        } else {

            IVLog(@"Incoming notification without TUCall");
        }

        return;
    }


    /*
     * Call status changes.
     */

    if ([name isEqualToString:
        @"TUCallCenterCallStatusChangedNotification"] ||
        [name isEqualToString:
        @"TUCallCenterCallStatusChangedInternalNotification"]) {

        id call =
            IVExtractCall(note);

        if (call) {

            /*
             * 如果已经有当前来电，
             * 不重复建立计时器。
             */

            if (!IVCurrentCall) {

                /*
                 * 只通过已有 selector 检查 incoming。
                 */

                SEL incomingSelector =
                    NSSelectorFromString(@"isIncoming");

                if ([call respondsToSelector:
                        incomingSelector]) {

                    BOOL (*msg)(id, SEL) =
                        (BOOL (*)(id, SEL))objc_msgSend;

                    BOOL incoming =
                        NO;

                    @try {

                        incoming =
                            msg(call,
                                incomingSelector);

                    } @catch (__unused NSException *exception) {

                        incoming = NO;
                    }

                    if (incoming) {

                        IVScheduleAnswer(call);

                        return;
                    }
                }
            }


            /*
             * 如果已经接听，状态改变可能意味着通话结束。
             */

            if (IVCurrentCall &&
                call == IVCurrentCall &&
                IVCallActive) {

                /*
                 * 不在这里调用 callStatus。
                 *
                 * 只依靠后续通知以及对象生命周期。
                 */

                IVLog(@"Current call status notification");
            }
        }
    }
}


#pragma mark ==================================================
#pragma mark Install Notifications
#pragma mark ==================================================

static void IVInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    NSArray *notifications = @[
        @"SBIncomingCallPendingNotification",
        @"TUCallCenterCallStatusChangedNotification",
        @"TUCallCenterCallStatusChangedInternalNotification",
        @"TUCallCenterModelChangedNotification",
        @"TUCallCenterModelStateChangedNotification"
    ];

    for (NSString *name in notifications) {

        [center addObserverForName:name
                            object:nil
                             queue:nil
                        usingBlock:
        ^(NSNotification *note) {

            IVHandleNotification(note);
        }];

        IVLog(@"Observer installed: %@",
              name);
    }
}


#pragma mark ==================================================
#pragma mark Constructor
#pragma mark ==================================================

%ctor
{
    @autoreleasepool {

        /*
         * 创建目录。
         */

        IVCreateDirectories();

        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"IndependentVoicemail FINAL LOADED");
        IVLog(@"========================================");

        IVLog(@"PID: %d",
              getpid());

        IVLog(@"Answer delay: %.1f seconds",
              IVAnswerDelay);

        IVLog(@"Greeting: %@",
              IVGreetingPath);

        IVLog(@"Recordings: %@",
              IVRecordingDirectory);


        /*
         * TelephonyUtilities
         */

        void *handle =
            dlopen(
                "/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities",
                RTLD_LAZY
            );

        if (handle) {

            IVLog(@"TelephonyUtilities loaded");

        } else {

            IVLog(@"TelephonyUtilities load failed");
        }


        /*
         * Runtime classes
         */

        IVLog(@"TUCall: %@",
              IVGetClass(@"TUCall")
                ? @"FOUND"
                : @"NOT FOUND");

        IVLog(@"TUProxyCall: %@",
              IVGetClass(@"TUProxyCall")
                ? @"FOUND"
                : @"NOT FOUND");

        IVLog(@"TUAnswerRequest: %@",
              IVGetClass(@"TUAnswerRequest")
                ? @"FOUND"
                : @"NOT FOUND");


        /*
         * Notification system
         */

        IVInstallObservers();


        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"INDEPENDENT VOICEMAIL FINAL ACTIVE");
        IVLog(@"AUTO ANSWER: ON");
        IVLog(@"DELAY: 20 SECONDS");
        IVLog(@"GREETING: ON");
        IVLog(@"RECORDING: ON");
        IVLog(@"MESSAGES INJECTION: OFF");
        IVLog(@"ANSWERINGMACHINE XS: NOT REQUIRED");
        IVLog(@"========================================");
    }
}

#import <Foundation/Foundation.h>
#import <unistd.h>
#import <stdarg.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

static NSTimer *IVTimer = nil;
static NSInteger IVRemaining = 20;
static BOOL IVIncomingCall = NO;

static void IVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *s =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:@"%@ %@\n",
         [NSDate date], s];

    NSFileHandle *h =
        [NSFileHandle fileHandleForWritingAtPath:IVLogPath];

    if (!h) {
        [[NSFileManager defaultManager]
            createFileAtPath:IVLogPath
            contents:nil
            attributes:nil];

        h =
            [NSFileHandle fileHandleForWritingAtPath:IVLogPath];
    }

    if (h) {
        [h seekToEndOfFile];

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [h writeData:data];
        [h closeFile];
    }
}

static void IVStopTimer(void) {
    if (IVTimer) {
        [IVTimer invalidate];
        IVTimer = nil;
    }

    IVIncomingCall = NO;
    IVRemaining = 20;
}

static void IVTimerTick(NSTimer *timer) {

    if (!IVIncomingCall) {
        IVStopTimer();
        return;
    }

    IVRemaining--;

    IVLog(@"Voicemail countdown: %ld seconds remaining",
          (long)IVRemaining);

    if (IVRemaining <= 0) {

        IVLog(@"================================");
        IVLog(@"VOICEMAIL ANSWER POINT REACHED");
        IVLog(@"AUTO ANSWER NOT ENABLED YET");
        IVLog(@"================================");

        IVStopTimer();
    }
}

static void IVIncomingCallDetected(void) {

    IVStopTimer();

    IVIncomingCall = YES;
    IVRemaining = 20;

    IVLog(@"================================");
    IVLog(@"INCOMING CALL DETECTED");
    IVLog(@"Starting voicemail countdown");
    IVLog(@"Delay: %ld seconds", (long)IVRemaining);
    IVLog(@"================================");

    IVTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:[NSBlockOperation blockOperationWithBlock:^{
        IVTimerTick(nil);
    }]
                                       selector:@selector(main)
                                       userInfo:nil
                                        repeats:YES];
}

static void IVNotification(NSNotification *note) {

    NSString *name = note.name;

    if ([name isEqualToString:@"SBIncomingCallPendingNotification"]) {

        IVIncomingCallDetected();
        return;
    }

    if ([name isEqualToString:@"SBCallCountChangedNotification"]) {

        IVLog(@"Call count changed");

        /*
         * 当系统报告电话数量发生变化时，
         * 暂时停止当前留言倒计时。
         *
         * 后续版本会改成真正判断 TUCall 状态。
         */
        return;
    }

    if ([name isEqualToString:
         @"TUCallCenterCallStatusChangedNotification"]) {

        IVLog(@"TUCall status changed");
        return;
    }

    if ([name isEqualToString:
         @"TUCallCenterCallStatusChangedInternalNotification"]) {

        IVLog(@"TUCall internal status changed");
        return;
    }
}

%ctor {
    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.4 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        NSArray *names = @[
            @"SBIncomingCallPendingNotification",
            @"SBCallCountChangedNotification",
            @"TUCallCenterCallStatusChangedNotification",
            @"TUCallCenterCallStatusChangedInternalNotification"
        ];

        for (NSString *name in names) {

            [center addObserverForName:name
                                object:nil
                                 queue:nil
                            usingBlock:^(NSNotification *note) {

                IVNotification(note);

            }];
        }

        IVLog(@"Voicemail state machine installed");
        IVLog(@"================================");
    }
}

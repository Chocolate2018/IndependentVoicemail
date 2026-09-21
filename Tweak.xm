#import <Foundation/Foundation.h>
#import <unistd.h>
#import <stdarg.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

static void IVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *s =
        [[NSString alloc] initWithFormat:format
                               arguments:args];

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

static BOOL IVEnabled(void) {
    NSNumber *n =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:@"IndependentVoicemailEnabled"];

    return n ? n.boolValue : YES;
}

static NSInteger IVDelay(void) {
    NSNumber *n =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:@"IndependentVoicemailDelay"];

    return n ? MAX(0, n.integerValue) : 20;
}

%ctor {
    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.1 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());
        IVLog(@"Enabled: %@", IVEnabled() ? @"YES" : @"NO");
        IVLog(@"Delay: %ld seconds", (long)IVDelay());
        IVLog(@"Audio session: NOT initialized");
        IVLog(@"================================");
    }
}

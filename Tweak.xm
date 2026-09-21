#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <stdarg.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

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

static void IVCallStateChanged(NSNotification *note) {
    IVLog(@"Notification received: %@",
          note.name);
}

%ctor {
    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.2 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());

        /*
         * Diagnostic only.
         * No automatic answering.
         * No recording.
         * No MobileSMS injection.
         */

        [[NSNotificationCenter defaultCenter]
            addObserverForName:nil
            object:nil
            queue:nil
            usingBlock:^(NSNotification *note) {

                NSString *name = note.name;

                if ([name rangeOfString:@"Call"
                                options:NSCaseInsensitiveSearch].location
                    != NSNotFound) {

                    IVCallStateChanged(note);
                }
            }];

        IVLog(@"Call notification monitor installed");
        IVLog(@"================================");
    }
}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

static void IVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [NSDate date], s];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:IVLogPath];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:IVLogPath
                                                 contents:nil
                                               attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:IVLogPath];
    }
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

/*
 IndependentVoicemail v1
 -----------------------
 This first build deliberately does NOT hook MobileSMS/Messages.

 The telephony answering/recording layer is isolated behind these
 functions so it can be adapted to the exact iOS 16.1.2 telephony
 classes observed on-device without putting any code into MobileSMS.
*/

static BOOL IVEnabled(void) {
    NSNumber *n = [[NSUserDefaults standardUserDefaults]
                   objectForKey:@"IndependentVoicemailEnabled"];
    return n ? n.boolValue : YES;
}

static NSInteger IVDelay(void) {
    NSNumber *n = [[NSUserDefaults standardUserDefaults]
                   objectForKey:@"IndependentVoicemailDelay"];
    return n ? MAX(0, n.integerValue) : 20;
}

static void IVPrepareAudioSession(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [s setCategory:AVAudioSessionCategoryPlayAndRecord
              mode:AVAudioSessionModeVoiceChat
           options:AVAudioSessionCategoryOptionAllowBluetooth
             error:&error];
    [s setActive:YES error:&error];

    if (error)
        IVLog(@"audio session error: %@", error);
    else
        IVLog(@"audio session ready");
}

%ctor {
    @autoreleasepool {
        IVLog(@"IndependentVoicemail v1 loaded");
        IVLog(@"enabled=%@ delay=%ld",
              IVEnabled() ? @"YES" : @"NO", (long)IVDelay());

        /*
         Do not touch MobileSMS.
         The actual CallServices hook is intentionally isolated until
         the target iOS 16.1.2 classes/methods are confirmed from a
         device log. This prevents a blind private-API hook from
         causing a SpringBoard/Phone crash.
        */
        IVPrepareAudioSession();
    }
}

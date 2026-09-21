#import <Foundation/Foundation.h>
#import <objc/runtime.h>
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

    [h seekToEndOfFile];

    [h writeData:
        [line dataUsingEncoding:NSUTF8StringEncoding]];

    [h closeFile];
}


static void IVInspectAnswerMethod(id call) {

    if (!call) {
        IVLog(@"Answer method inspection: call=nil");
        return;
    }

    Class cls = object_getClass(call);

    IVLog(@"================================");
    IVLog(@"ANSWER METHOD INSPECTION");
    IVLog(@"Class: %@", NSStringFromClass(cls));

    SEL sel = @selector(answerWithRequest:);

    if (![call respondsToSelector:sel]) {
        IVLog(@"ERROR: answerWithRequest: NOT FOUND");
        return;
    }

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method) {
        IVLog(@"ERROR: Method object unavailable");
        return;
    }

    const char *types =
        method_getTypeEncoding(method);

    if (types) {
        IVLog(@"Type encoding: %s", types);
    }

    unsigned int argCount =
        method_getNumberOfArguments(method);

    IVLog(@"Argument count: %u", argCount);

    for (unsigned int i = 0; i < argCount; i++) {

        char buffer[256];

        method_getArgumentType(
            method,
            i,
            buffer,
            sizeof(buffer)
        );

        IVLog(@"Argument %u type: %s",
              i,
              buffer);
    }

    char returnBuffer[256];

    method_getReturnType(
        method,
        returnBuffer,
        sizeof(returnBuffer)
    );

    IVLog(@"Return type: %s",
          returnBuffer);

    IVLog(@"================================");
}


static void IVCallNotification(
    NSNotification *note
) {

    id call = note.object;

    if (!call)
        return;

    Class cls = object_getClass(call);

    if (!cls)
        return;

    NSString *className =
        NSStringFromClass(cls);

    if (![className isEqualToString:@"TUProxyCall"])
        return;

    NSString *status = nil;

    if ([call respondsToSelector:@selector(callStatus)]) {
        @try {
            status =
            [call performSelector:@selector(callStatus)];
        }
        @catch (...) {
            status = nil;
        }
    }

    IVLog(@"--------------------------------");
    IVLog(@"TUProxyCall notification");
    IVLog(@"Notification: %@", note.name);
    IVLog(@"Status: %@", status);

    IVInspectAnswerMethod(call);

    IVLog(@"--------------------------------");
}


%ctor {

    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.6 LOADED");
        IVLog(@"Process: %s", getprogname());
        IVLog(@"PID: %d", getpid());

        NSNotificationCenter *nc =
            [NSNotificationCenter defaultCenter];

        [nc addObserverForName:
                @"TUCallCenterCallStatusChangedNotification"
            object:nil
             queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {

            IVCallNotification(note);
        }];


        [nc addObserverForName:
                @"TUCallCenterCallStatusChangedInternalNotification"
            object:nil
             queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {

            IVCallNotification(note);
        }];


        IVLog(@"v1.6 answer method inspector installed");
        IVLog(@"================================");
    }
}

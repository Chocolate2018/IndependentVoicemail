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

    if (h) {
        [h seekToEndOfFile];

        [h writeData:
            [line dataUsingEncoding:NSUTF8StringEncoding]];

        [h closeFile];
    }
}


static void IVInspectClass(Class cls) {

    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"SAFE CLASS INSPECTION");
    IVLog(@"Class: %@", NSStringFromClass(cls));

    Method answerMethod =
        class_getInstanceMethod(
            cls,
            @selector(answerWithRequest:)
        );

    if (!answerMethod) {
        IVLog(@"answerWithRequest: NOT FOUND");
    }
    else {

        const char *types =
            method_getTypeEncoding(answerMethod);

        if (types)
            IVLog(@"Type encoding: %s", types);

        unsigned int count =
            method_getNumberOfArguments(answerMethod);

        IVLog(@"Argument count: %u", count);

        for (unsigned int i = 0;
             i < count;
             i++) {

            char buffer[256] = {0};

            method_getArgumentType(
                answerMethod,
                i,
                buffer,
                sizeof(buffer)
            );

            IVLog(@"Argument %u type: %s",
                  i,
                  buffer);
        }

        char returnBuffer[256] = {0};

        method_getReturnType(
            answerMethod,
            returnBuffer,
            sizeof(returnBuffer)
        );

        IVLog(@"Return type: %s",
              returnBuffer);
    }

    IVLog(@"================================");
}


static void IVHandleNotification(
    NSNotification *note
) {

    id object = note.object;

    if (!object)
        return;

    Class cls = object_getClass(object);

    if (!cls)
        return;

    NSString *name =
        NSStringFromClass(cls);

    if (![name isEqualToString:@"TUProxyCall"])
        return;

    IVLog(@"--------------------------------");
    IVLog(@"TUProxyCall detected");
    IVLog(@"Notification: %@", note.name);

    /*
     * IMPORTANT:
     * Do NOT call any TUProxyCall instance method.
     * Only inspect the class metadata.
     */

    IVInspectClass(cls);

    IVLog(@"--------------------------------");
}


%ctor {

    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.6.1 LOADED");
        IVLog(@"Process: %s", getprogname());
        IVLog(@"PID: %d", getpid());

        NSNotificationCenter *nc =
            [NSNotificationCenter defaultCenter];

        [nc addObserverForName:
                @"TUCallCenterCallStatusChangedNotification"
            object:nil
             queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {

            IVHandleNotification(note);
        }];


        [nc addObserverForName:
                @"TUCallCenterCallStatusChangedInternalNotification"
            object:nil
             queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {

            IVHandleNotification(note);
        }];


        IVLog(@"Safe inspector installed");
        IVLog(@"No TUProxyCall methods will be invoked");
        IVLog(@"================================");
    }
}

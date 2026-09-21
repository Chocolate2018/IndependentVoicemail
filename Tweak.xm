#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemail/IndependentVoicemailV2.log";

static void IVLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSString *line = [NSString stringWithFormat:
        @"[%@] %@\n",
        [NSDate date],
        message];

    [[NSFileManager defaultManager]
        createFileAtPath:IVLogPath
        contents:nil
        attributes:nil];

    NSFileHandle *handle =
        [NSFileHandle fileHandleForWritingAtPath:IVLogPath];

    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

static void IVInspectClass(Class cls)
{
    if (!cls) {
        IVLog(@"Class not found");
        return;
    }

    IVLog(@"========================================");
    IVLog(@"CLASS: %s", class_getName(cls));
    IVLog(@"========================================");

    Class meta = object_getClass(cls);

    unsigned int count = 0;
    Method *methods = class_copyMethodList(meta, &count);

    IVLog(@"Class methods: %u", count);

    for (unsigned int i = 0; i < count; i++) {

        Method method = methods[i];

        SEL selector = method_getName(method);
        const char *name = sel_getName(selector);
        const char *types = method_getTypeEncoding(method);

        NSString *lower =
            [[NSString stringWithUTF8String:name] lowercaseString];

        if ([lower containsString:@"request"] ||
            [lower containsString:@"answer"] ||
            [lower containsString:@"call"]) {

            IVLog(@"CLASS METHOD: %s", name);
            IVLog(@"TYPE: %s", types);
        }
    }

    free(methods);

    unsigned int initCount = 0;
    Method *instanceMethods = class_copyMethodList(cls, &initCount);

    IVLog(@"Instance methods: %u", initCount);

    for (unsigned int i = 0; i < initCount; i++) {

        Method method = instanceMethods[i];

        SEL selector = method_getName(method);
        const char *name = sel_getName(selector);
        const char *types = method_getTypeEncoding(method);

        NSString *lower =
            [[NSString stringWithUTF8String:name] lowercaseString];

        if ([lower containsString:@"request"] ||
            [lower containsString:@"answer"] ||
            [lower containsString:@"init"]) {

            IVLog(@"INSTANCE METHOD: %s", name);
            IVLog(@"TYPE: %s", types);
        }
    }

    free(instanceMethods);
}

static void IVInspectAnswerMethod(Class cls)
{
    if (!cls) return;

    SEL selector = @selector(answerWithRequest:);

    Method method = class_getInstanceMethod(cls, selector);

    if (!method) {
        IVLog(@"answerWithRequest: NOT FOUND");
        return;
    }

    const char *types = method_getTypeEncoding(method);

    Class owner = class_getSuperclass(cls);

    while (owner) {

        Method parentMethod =
            class_getInstanceMethod(owner, selector);

        if (parentMethod == method) {
            IVLog(@"answerWithRequest: defined by %s",
                  class_getName(owner));
            break;
        }

        owner = class_getSuperclass(owner);
    }

    IVLog(@"answerWithRequest: encoding = %s", types);
}

static void IVInspectTUClasses(void)
{
    IVLog(@"========================================");
    IVLog(@"IndependentVoicemail v2.1");
    IVLog(@"SAFE TUAnswerRequest DIAGNOSTIC");
    IVLog(@"========================================");

    void *handle =
        dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities",
               RTLD_LAZY);

    if (handle) {
        IVLog(@"TelephonyUtilities loaded");
        dlclose(handle);
    } else {
        IVLog(@"TelephonyUtilities load failed");
    }

    Class TUCallClass = NSClassFromString(@"TUCall");
    Class TUProxyCallClass = NSClassFromString(@"TUProxyCall");
    Class TUAnswerRequestClass = NSClassFromString(@"TUAnswerRequest");

    IVLog(@"TUCall: %@", TUCallClass ? @"FOUND" : @"NOT FOUND");
    IVLog(@"TUProxyCall: %@", TUProxyCallClass ? @"FOUND" : @"NOT FOUND");
    IVLog(@"TUAnswerRequest: %@", TUAnswerRequestClass ? @"FOUND" : @"NOT FOUND");

    if (TUAnswerRequestClass) {
        IVInspectClass(TUAnswerRequestClass);
    }

    if (TUCallClass) {
        IVInspectAnswerMethod(TUCallClass);
    }

    if (TUProxyCallClass) {
        IVInspectAnswerMethod(TUProxyCallClass);
    }

    IVLog(@"========================================");
    IVLog(@"DIAGNOSTIC COMPLETE");
    IVLog(@"NO ANSWER CALL WAS MADE");
    IVLog(@"========================================");
}

static void IVInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    NSArray *names = @[
        @"SBIncomingCallPendingNotification",
        @"TUCallCenterCallStatusChangedNotification",
        @"TUCallCenterCallStatusChangedInternalNotification",
        @"TUCallCenterModelChangedNotification",
        @"TUCallCenterModelStateChangedNotification"
    ];

    for (NSString *name in names) {

        [center addObserverForName:name
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {

            IVLog(@"Notification: %@", note.name);

            if ([note.name
                 isEqualToString:@"SBIncomingCallPendingNotification"]) {

                IVLog(@"Incoming call notification captured");
                IVLog(@"NO automatic answer in v2.1");

            }
        }];
    }

    IVLog(@"Observers installed");
}

%ctor
{
    @autoreleasepool {

        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"IndependentVoicemail v2.1 LOADED");
        IVLog(@"========================================");

        IVInspectTUClasses();
        IVInstallObservers();

        IVLog(@"========================================");
        IVLog(@"v2.1 SAFE DIAGNOSTIC ACTIVE");
        IVLog(@"AUTO ANSWER: OFF");
        IVLog(@"INSTANCE METHOD CALLS: OFF");
        IVLog(@"ANSWERWITHREQUEST: OFF");
        IVLog(@"========================================");
    }
}

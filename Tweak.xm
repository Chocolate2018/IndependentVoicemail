#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

static void IVLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:@"%@ %@\n",
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
        [handle seekToEndOfFile];

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [handle writeData:data];
        [handle closeFile];
    }
}


/*
 * ------------------------------------------------------------
 * Safe class hierarchy inspection
 * ------------------------------------------------------------
 */

static void IVInspectHierarchy(Class cls)
{
    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"CLASS HIERARCHY");
    IVLog(@"================================");

    Class current = cls;
    int level = 0;

    while (current) {

        IVLog(@"LEVEL %d: %s",
              level,
              class_getName(current));

        current = class_getSuperclass(current);
        level++;

        if (level > 10)
            break;
    }
}


/*
 * ------------------------------------------------------------
 * Find the class that actually implements a selector.
 *
 * IMPORTANT:
 * This only examines Objective-C metadata.
 * It does NOT invoke the method.
 * ------------------------------------------------------------
 */

static Class IVFindDefiningClass(Class cls, SEL selector)
{
    Class current = cls;

    while (current) {

        Method method =
            class_getInstanceMethod(current, selector);

        if (method) {

            /*
             * class_getInstanceMethod() may return an inherited
             * method, therefore check the direct method list.
             */

            unsigned int count = 0;

            Method *methods =
                class_copyMethodList(current, &count);

            for (unsigned int i = 0; i < count; i++) {

                SEL currentSEL =
                    method_getName(methods[i]);

                if (currentSEL == selector) {

                    free(methods);
                    return current;
                }
            }

            free(methods);
        }

        current = class_getSuperclass(current);
    }

    return Nil;
}


/*
 * ------------------------------------------------------------
 * Inspect implementation image.
 *
 * Metadata only. No method execution.
 * ------------------------------------------------------------
 */

static void IVInspectImplementation(Class cls, SEL selector)
{
    if (!cls || !selector)
        return;

    Method method =
        class_getInstanceMethod(cls, selector);

    if (!method) {
        IVLog(@"METHOD NOT FOUND: %s",
              sel_getName(selector));
        return;
    }

    IMP imp =
        method_getImplementation(method);

    const char *encoding =
        method_getTypeEncoding(method);

    Class owner =
        IVFindDefiningClass(cls, selector);

    IVLog(@"--------------------------------");
    IVLog(@"SELECTOR: %s",
          sel_getName(selector));

    IVLog(@"REQUESTED CLASS: %s",
          class_getName(cls));

    if (owner) {
        IVLog(@"DEFINING CLASS: %s",
              class_getName(owner));
    } else {
        IVLog(@"DEFINING CLASS: UNKNOWN");
    }

    IVLog(@"TYPE ENCODING: %s",
          encoding ? encoding : "(null)");

    IVLog(@"IMP ADDRESS: %p",
          imp);

    Dl_info info;

    memset(&info, 0, sizeof(info));

    if (imp && dladdr((void *)imp, &info)) {

        if (info.dli_fname) {
            IVLog(@"IMPLEMENTATION IMAGE: %s",
                  info.dli_fname);
        }

        if (info.dli_sname) {
            IVLog(@"IMPLEMENTATION SYMBOL: %s",
                  info.dli_sname);
        }

        if (info.dli_saddr) {
            IVLog(@"IMPLEMENTATION SYMBOL ADDRESS: %p",
                  info.dli_saddr);
        }

    } else {

        IVLog(@"IMPLEMENTATION IMAGE: unavailable");
    }

    IVLog(@"--------------------------------");
}


/*
 * ------------------------------------------------------------
 * Safe direct method scanner.
 *
 * Only scans method names.
 * Never invokes anything.
 * ------------------------------------------------------------
 */

static BOOL IVIsInterestingSelector(SEL selector)
{
    if (!selector)
        return NO;

    NSString *name =
        NSStringFromSelector(selector);

    NSString *lower =
        [name lowercaseString];

    NSArray *keywords = @[
        @"request",
        @"answer",
        @"action",
        @"service",
        @"delegate",
        @"call"
    ];

    for (NSString *keyword in keywords) {

        if ([lower containsString:keyword])
            return YES;
    }

    return NO;
}


static void IVScanDirectMethods(Class cls)
{
    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"DIRECT METHOD SCAN");
    IVLog(@"CLASS: %s",
          class_getName(cls));
    IVLog(@"================================");

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    if (!methods) {
        IVLog(@"No direct methods");
        return;
    }

    IVLog(@"DIRECT METHOD COUNT: %u",
          count);

    unsigned int printed = 0;

    for (unsigned int i = 0; i < count; i++) {

        SEL selector =
            method_getName(methods[i]);

        if (!IVIsInterestingSelector(selector))
            continue;

        const char *encoding =
            method_getTypeEncoding(methods[i]);

        IVLog(@"METHOD: %s",
              sel_getName(selector));

        IVLog(@"ENCODING: %s",
              encoding ? encoding : "(null)");

        printed++;

        if (printed >= 80) {
            IVLog(@"METHOD OUTPUT LIMIT REACHED");
            break;
        }
    }

    IVLog(@"INTERESTING METHODS PRINTED: %u",
          printed);

    free(methods);
}


/*
 * ------------------------------------------------------------
 * Inspect selected selectors.
 *
 * These are metadata operations only.
 * ------------------------------------------------------------
 */

static void IVInspectKnownSelectors(Class cls)
{
    if (!cls)
        return;

    NSArray *selectors = @[
        @"answerWithRequest:",
        @"initWithCall:",
        @"updateWithCall:",
        @"callServicesInterface",
        @"callNotificationManager",
        @"callCenter",
        @"callStatus",
        @"callUUID",
        @"shouldSuppressInCallUI"
    ];

    for (NSString *name in selectors) {

        SEL selector =
            NSSelectorFromString(name);

        IVInspectImplementation(cls, selector);
    }
}


/*
 * ------------------------------------------------------------
 * Notification observer
 *
 * We only log notification arrival.
 * We do NOT call methods on the notification object.
 * ------------------------------------------------------------
 */

static void IVNotification(NSNotification *note)
{
    if (!note)
        return;

    NSString *name = note.name;

    if (![name containsString:@"TUCallCenter"])
        return;

    IVLog(@"================================");
    IVLog(@"CALL NOTIFICATION");
    IVLog(@"NAME: %@", name);
    IVLog(@"OBJECT CLASS: %@",
          note.object ? NSStringFromClass([note.object class])
                       : @"(nil)");
    IVLog(@"USERINFO CLASS: %@",
          note.userInfo ? NSStringFromClass([note.userInfo class])
                        : @"(nil)");
    IVLog(@"================================");
}


/*
 * ------------------------------------------------------------
 * Main
 * ------------------------------------------------------------
 */

%ctor
{
    @autoreleasepool {

        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"IndependentVoicemail v1.9 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());
        IVLog(@"========================================");

        Class tuCall =
            objc_getClass("TUCall");

        Class tuProxyCall =
            objc_getClass("TUProxyCall");

        if (tuCall) {

            IVLog(@"TUCall FOUND");

            IVInspectHierarchy(tuCall);

            IVInspectKnownSelectors(tuCall);

            IVScanDirectMethods(tuCall);

        } else {

            IVLog(@"TUCall NOT FOUND");
        }


        if (tuProxyCall) {

            IVLog(@"TUProxyCall FOUND");

            IVInspectHierarchy(tuProxyCall);

            IVInspectKnownSelectors(tuProxyCall);

            IVScanDirectMethods(tuProxyCall);

        } else {

            IVLog(@"TUProxyCall NOT FOUND");
        }


        /*
         * Only observe notifications.
         */

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        [center addObserverForName:
            @"TUCallCenterCallStatusChangedNotification"
            object:nil
            queue:nil
            usingBlock:^(NSNotification *note) {

                IVNotification(note);
            }];


        [center addObserverForName:
            @"TUCallCenterCallStatusChangedInternalNotification"
            object:nil
            queue:nil
            usingBlock:^(NSNotification *note) {

                IVNotification(note);
            }];


        IVLog(@"v1.9 SAFE INSPECTION INSTALLED");
        IVLog(@"NO TUCall INSTANCE METHODS INVOKED");
        IVLog(@"NO TUProxyCall INSTANCE METHODS INVOKED");
        IVLog(@"========================================");
    }
}

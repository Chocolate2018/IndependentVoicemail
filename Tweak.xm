#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";


#pragma mark - Logging

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


#pragma mark - Safe Runtime Helpers

/*
 * v2.0 NEVER invokes TUCall/TUProxyCall instance methods.
 *
 * The following functions only inspect Objective-C metadata.
 */


static NSString *IVClassName(id object)
{
    if (!object)
        return @"(nil)";

    Class cls = object_getClass(object);

    if (!cls)
        return @"(unknown)";

    return NSStringFromClass(cls);
}


static NSString *IVObjectDescriptionSafe(id object)
{
    /*
     * Do NOT call -description on arbitrary telephony objects.
     *
     * v2.0 intentionally avoids it because a private object's
     * description implementation could itself execute private
     * code.
     */

    if (!object)
        return @"(nil)";

    return [NSString stringWithFormat:@"<%@ %p>",
            IVClassName(object),
            object];
}


#pragma mark - Class Hierarchy

static void IVInspectHierarchy(Class cls)
{
    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"CLASS HIERARCHY");
    IVLog(@"CLASS: %@", NSStringFromClass(cls));
    IVLog(@"================================");

    Class current = cls;

    int level = 0;

    while (current) {

        IVLog(@"LEVEL %d: %@",
              level,
              NSStringFromClass(current));

        current = class_getSuperclass(current);

        level++;

        if (level > 10)
            break;
    }
}


#pragma mark - Instance Method Metadata

static void IVInspectMethodMetadata(Class cls,
                                    SEL selector)
{
    if (!cls || !selector)
        return;

    Method method =
        class_getInstanceMethod(cls, selector);

    if (!method) {

        IVLog(@"METHOD NOT FOUND: %@",
              NSStringFromSelector(selector));

        return;
    }

    const char *encoding =
        method_getTypeEncoding(method);

    unsigned int argumentCount =
        method_getNumberOfArguments(method);

    IVLog(@"--------------------------------");
    IVLog(@"METHOD METADATA");
    IVLog(@"CLASS: %@", NSStringFromClass(cls));
    IVLog(@"SELECTOR: %@",
          NSStringFromSelector(selector));

    IVLog(@"ENCODING: %s",
          encoding ? encoding : "(null)");

    IVLog(@"ARGUMENT COUNT: %u",
          argumentCount);

    for (unsigned int i = 0;
         i < argumentCount;
         i++) {

        char buffer[256];

        memset(buffer, 0, sizeof(buffer));

        method_getArgumentType(method,
                               i,
                               buffer,
                               sizeof(buffer));

        IVLog(@"ARG %u: %s",
              i,
              buffer);
    }

    char returnBuffer[256];

    memset(returnBuffer, 0, sizeof(returnBuffer));

    method_getReturnType(method,
                          returnBuffer,
                          sizeof(returnBuffer));

    IVLog(@"RETURN: %s",
          returnBuffer);

    IVLog(@"--------------------------------");
}


#pragma mark - Direct Instance Method Scan

static BOOL IVInterestingMethodName(NSString *name)
{
    if (!name)
        return NO;

    NSString *lower =
        [name lowercaseString];

    NSArray *keywords = @[
        @"request",
        @"answer",
        @"action",
        @"service",
        @"delegate"
    ];

    for (NSString *keyword in keywords) {

        if ([lower containsString:keyword])
            return YES;
    }

    return NO;
}


static void IVScanInstanceMethods(Class cls)
{
    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"INSTANCE METHOD SCAN");
    IVLog(@"CLASS: %@",
          NSStringFromClass(cls));
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

    for (unsigned int i = 0;
         i < count;
         i++) {

        SEL selector =
            method_getName(methods[i]);

        NSString *name =
            NSStringFromSelector(selector);

        if (!IVInterestingMethodName(name))
            continue;

        const char *encoding =
            method_getTypeEncoding(methods[i]);

        IVLog(@"METHOD: %@", name);

        IVLog(@"ENCODING: %s",
              encoding ? encoding : "(null)");

        printed++;

        if (printed >= 100) {

            IVLog(@"INSTANCE METHOD OUTPUT LIMIT");

            break;
        }
    }

    IVLog(@"INTERESTING INSTANCE METHODS: %u",
          printed);

    free(methods);
}


#pragma mark - Class Method Scan

/*
 * This is one of the main new parts of v2.0.
 *
 * We inspect +class methods only.
 *
 * NOTHING IS INVOKED.
 */

static BOOL IVInterestingClassMethodName(NSString *name)
{
    if (!name)
        return NO;

    NSString *lower =
        [name lowercaseString];

    NSArray *keywords = @[
        @"request",
        @"answer",
        @"action",
        @"call",
        @"service",
        @"proxy"
    ];

    for (NSString *keyword in keywords) {

        if ([lower containsString:keyword])
            return YES;
    }

    return NO;
}


static void IVScanClassMethods(Class cls)
{
    if (!cls)
        return;

    IVLog(@"================================");
    IVLog(@"CLASS METHOD SCAN");
    IVLog(@"CLASS: %@",
          NSStringFromClass(cls));
    IVLog(@"================================");

    Class metaClass =
        object_getClass(cls);

    if (!metaClass) {

        IVLog(@"METACLASS NOT FOUND");

        return;
    }

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(metaClass, &count);

    if (!methods) {

        IVLog(@"No class methods");

        return;
    }

    IVLog(@"DIRECT CLASS METHOD COUNT: %u",
          count);

    unsigned int printed = 0;

    for (unsigned int i = 0;
         i < count;
         i++) {

        SEL selector =
            method_getName(methods[i]);

        NSString *name =
            NSStringFromSelector(selector);

        if (!IVInterestingClassMethodName(name))
            continue;

        const char *encoding =
            method_getTypeEncoding(methods[i]);

        IVLog(@"CLASS METHOD: +%@", name);

        IVLog(@"ENCODING: %s",
              encoding ? encoding : "(null)");

        unsigned int args =
            method_getNumberOfArguments(methods[i]);

        IVLog(@"ARGUMENT COUNT: %u",
              args);

        printed++;

        if (printed >= 100) {

            IVLog(@"CLASS METHOD OUTPUT LIMIT");

            break;
        }
    }

    IVLog(@"INTERESTING CLASS METHODS: %u",
          printed);

    free(methods);
}


#pragma mark - Selected Metadata

static void IVInspectSelectedMethods(Class cls)
{
    if (!cls)
        return;

    NSArray *names = @[
        @"answerWithRequest:",
        @"initWithCall:",
        @"updateWithCall:",
        @"callServicesInterface",
        @"callNotificationManager",
        @"callCenter",
        @"callStatus",
        @"callUUID",
        @"shouldSuppressInCallUI",
        @"dialRequestForRedial",
        @"proxyCallActionsDelegate"
    ];

    for (NSString *name in names) {

        SEL selector =
            NSSelectorFromString(name);

        IVInspectMethodMetadata(cls,
                                selector);
    }
}


#pragma mark - Notification Inspection

/*
 * v2.0 notification inspection.
 *
 * We inspect:
 *
 *   notification name
 *   object class
 *   userInfo keys
 *   userInfo value classes
 *
 * We DO NOT call methods on the object.
 */

static void IVInspectUserInfo(NSDictionary *userInfo)
{
    if (!userInfo) {

        IVLog(@"USERINFO: (nil)");

        return;
    }

    IVLog(@"USERINFO CLASS: %@",
          NSStringFromClass([userInfo class]));

    IVLog(@"USERINFO COUNT: %lu",
          (unsigned long)[userInfo count]);

    for (id key in userInfo) {

        id value = userInfo[key];

        IVLog(@"USERINFO KEY: %@",
              [key isKindOfClass:[NSString class]]
                  ? key
                  : IVObjectDescriptionSafe(key));

        IVLog(@"USERINFO VALUE CLASS: %@",
              IVClassName(value));

        /*
         * Do not call description on arbitrary private
         * telephony objects.
         */

        IVLog(@"USERINFO VALUE: %@",
              IVObjectDescriptionSafe(value));
    }
}


static void IVHandleCallNotification(NSNotification *note)
{
    if (!note)
        return;

    NSString *name =
        note.name;

    if (!name)
        return;

    /*
     * Only TUCallCenter notifications.
     */

    if (![name containsString:@"TUCallCenter"])
        return;

    IVLog(@"");
    IVLog(@"========================================");
    IVLog(@"CALL NOTIFICATION DETECTED");
    IVLog(@"========================================");

    IVLog(@"NOTIFICATION: %@",
          name);

    /*
     * IMPORTANT:
     * We only inspect the Objective-C class.
     */

    if (note.object) {

        IVLog(@"OBJECT CLASS: %@",
              IVClassName(note.object));

        IVLog(@"OBJECT POINTER: %p",
              note.object);

    } else {

        IVLog(@"OBJECT: (nil)");
    }

    IVInspectUserInfo(note.userInfo);

    IVLog(@"========================================");
}


#pragma mark - Notification Installation

static void IVInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    NSArray *names = @[
        @"TUCallCenterCallStatusChangedNotification",
        @"TUCallCenterCallStatusChangedInternalNotification",
        @"TUCallCenterCallerIDChangedNotification",
        @"TUCallCenterDisplayContextChangedNotification",
        @"TUCallCenterModelChangedNotification",
        @"TUCallCenterModelStateChangedNotification",
        @"TUCallCenterProviderContextChangedNotification"
    ];

    for (NSString *name in names) {

        [center addObserverForName:name
                            object:nil
                             queue:nil
                        usingBlock:^(NSNotification *note) {

            IVHandleCallNotification(note);
        }];

        IVLog(@"OBSERVER INSTALLED: %@",
              name);
    }
}


#pragma mark - Main

%ctor
{
    @autoreleasepool {

        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"IndependentVoicemail v2.0 LOADED");
        IVLog(@"========================================");

        IVLog(@"PROCESS: SpringBoard");
        IVLog(@"PID: %d", getpid());

        /*
         * ----------------------------------------------------
         * TUCall
         * ----------------------------------------------------
         */

        Class tuCall =
            objc_getClass("TUCall");

        if (tuCall) {

            IVLog(@"TUCall FOUND");

            IVInspectHierarchy(tuCall);

            IVInspectSelectedMethods(tuCall);

            IVScanInstanceMethods(tuCall);

            IVScanClassMethods(tuCall);

        } else {

            IVLog(@"TUCall NOT FOUND");
        }


        /*
         * ----------------------------------------------------
         * TUProxyCall
         * ----------------------------------------------------
         */

        Class tuProxyCall =
            objc_getClass("TUProxyCall");

        if (tuProxyCall) {

            IVLog(@"TUProxyCall FOUND");

            IVInspectHierarchy(tuProxyCall);

            IVInspectSelectedMethods(tuProxyCall);

            IVScanInstanceMethods(tuProxyCall);

            IVScanClassMethods(tuProxyCall);

        } else {

            IVLog(@"TUProxyCall NOT FOUND");
        }


        /*
         * ----------------------------------------------------
         * Notifications
         * ----------------------------------------------------
         */

        IVInstallObservers();


        /*
         * ----------------------------------------------------
         * Safety banner
         * ----------------------------------------------------
         */

        IVLog(@"");
        IVLog(@"========================================");
        IVLog(@"v2.0 SAFE INSPECTION ACTIVE");
        IVLog(@"========================================");

        IVLog(@"NO answerWithRequest: INVOCATION");
        IVLog(@"NO callStatus INVOCATION");
        IVLog(@"NO callUUID INVOCATION");
        IVLog(@"NO callServicesInterface INVOCATION");
        IVLog(@"NO proxyCallActionsDelegate INVOCATION");
        IVLog(@"NO updateWithCall: INVOCATION");
        IVLog(@"NO TUCall INSTANCE METHOD INVOCATION");
        IVLog(@"NO TUProxyCall INSTANCE METHOD INVOCATION");

        IVLog(@"========================================");
    }
}

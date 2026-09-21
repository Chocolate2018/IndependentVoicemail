#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <stdarg.h>

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
         [NSDate date], message];

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

/* ---------------------------------------------------------
   打印一个类的继承关系
   --------------------------------------------------------- */

static void IVInspectClassHierarchy(Class cls)
{
    IVLog(@"----- CLASS HIERARCHY -----");

    int level = 0;

    while (cls && level < 12) {

        IVLog(@"Level %d: %s",
              level,
              class_getName(cls));

        cls = class_getSuperclass(cls);
        level++;
    }

    IVLog(@"---------------------------");
}

/* ---------------------------------------------------------
   安全检查 answerWithRequest:
   只读取 Method metadata
   不执行方法
   --------------------------------------------------------- */

static void IVInspectAnswerMethod(Class cls)
{
    if (!cls)
        return;

    SEL selector =
        NSSelectorFromString(@"answerWithRequest:");

    Method method =
        class_getInstanceMethod(cls, selector);

    if (!method) {
        IVLog(@"answerWithRequest: NOT FOUND");
        return;
    }

    IVLog(@"----- answerWithRequest: -----");

    const char *encoding =
        method_getTypeEncoding(method);

    IVLog(@"Encoding: %s",
          encoding ? encoding : "(null)");

    unsigned int count =
        method_getNumberOfArguments(method);

    IVLog(@"Argument count: %u", count);

    for (unsigned int i = 0; i < count; i++) {

        char buffer[256] = {0};

        method_getArgumentType(method,
                               i,
                               buffer,
                               sizeof(buffer));

        IVLog(@"Argument %u type: %s",
              i,
              buffer);
    }

    char returnType[256] = {0};

    method_getReturnType(method,
                         returnType,
                         sizeof(returnType));

    IVLog(@"Return type: %s",
          returnType);

    IVLog(@"------------------------------");
}

/* ---------------------------------------------------------
   搜索类中名字与 Request / Answer / Call 有关的方法
   只读取方法名，不执行
   --------------------------------------------------------- */

static void IVInspectRelatedMethods(Class cls)
{
    if (!cls)
        return;

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    if (!methods) {
        IVLog(@"No instance methods found");
        return;
    }

    IVLog(@"----- RELATED INSTANCE METHODS -----");

    int found = 0;

    for (unsigned int i = 0; i < count; i++) {

        SEL selector =
            method_getName(methods[i]);

        const char *name =
            sel_getName(selector);

        if (!name)
            continue;

        NSString *s =
            [NSString stringWithUTF8String:name];

        NSString *lower =
            [s lowercaseString];

        BOOL related =
            [lower containsString:@"request"] ||
            [lower containsString:@"answer"] ||
            [lower containsString:@"call"];

        if (related) {

            const char *encoding =
                method_getTypeEncoding(methods[i]);

            IVLog(@"METHOD: %s",
                  name);

            IVLog(@"  ENCODING: %s",
                  encoding ? encoding : "(null)");

            found++;

            /*
             * 防止日志无限膨胀
             */
            if (found >= 80) {
                IVLog(@"Method output limited to 80 entries");
                break;
            }
        }
    }

    if (found == 0) {
        IVLog(@"No Request/Answer/Call related methods found");
    }

    IVLog(@"Related method count: %d",
          found);

    IVLog(@"------------------------------------");

    free(methods);
}

/* ---------------------------------------------------------
   检查 TUProxyCall
   --------------------------------------------------------- */

static void IVInspectTUProxyCall(id object)
{
    if (!object)
        return;

    Class cls =
        object_getClass(object);

    if (!cls)
        return;

    const char *className =
        class_getName(cls);

    if (!className)
        return;

    if (strcmp(className, "TUProxyCall") != 0)
        return;

    IVLog(@"================================");
    IVLog(@"TUProxyCall detected");
    IVLog(@"================================");

    IVLog(@"Class: %s",
          className);

    /*
     * 1. 继承关系
     */
    IVInspectClassHierarchy(cls);

    /*
     * 2. answerWithRequest: 元数据
     */
    IVInspectAnswerMethod(cls);

    /*
     * 3. 相关方法名
     */
    IVInspectRelatedMethods(cls);

    IVLog(@"================================");
    IVLog(@"SAFE INSPECTION FINISHED");
    IVLog(@"NO TUProxyCall METHODS INVOKED");
    IVLog(@"NO ANSWER REQUEST SENT");
    IVLog(@"================================");
}

/* ---------------------------------------------------------
   通知回调
   --------------------------------------------------------- */

static void IVCallNotification(
    NSNotification *notification)
{
    if (!notification)
        return;

    id object =
        notification.object;

    if (!object)
        return;

    Class cls =
        object_getClass(object);

    if (!cls)
        return;

    const char *className =
        class_getName(cls);

    if (!className)
        return;

    if (strcmp(className, "TUProxyCall") != 0)
        return;

    NSString *name =
        notification.name;

    IVLog(@"--------------------------------");
    IVLog(@"Notification: %@",
          name);

    IVInspectTUProxyCall(object);
}

/* ---------------------------------------------------------
   初始化
   --------------------------------------------------------- */

%ctor
{
    @autoreleasepool {

        /*
         * 只允许在 SpringBoard 中工作
         */
        NSString *process =
            [[NSProcessInfo processInfo] processName];

        if (![process isEqualToString:@"SpringBoard"]) {
            return;
        }

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.7 LOADED");
        IVLog(@"Process: %@", process);
        IVLog(@"PID: %d", getpid());
        IVLog(@"================================");

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        [center addObserverForName:
                    @"TUCallCenterCallStatusChangedNotification"
                object:nil
                 queue:nil
            usingBlock:^(NSNotification *note) {

                IVCallNotification(note);
            }];

        [center addObserverForName:
                    @"TUCallCenterCallStatusChangedInternalNotification"
                object:nil
                 queue:nil
            usingBlock:^(NSNotification *note) {

                IVCallNotification(note);
            }];

        IVLog(@"v1.7 safe runtime inspector installed");
        IVLog(@"Monitoring TUProxyCall only");
        IVLog(@"NO call-control methods will be invoked");
        IVLog(@"================================");
    }
}

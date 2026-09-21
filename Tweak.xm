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

/* =========================================================
   方法签名安全检查
   ========================================================= */

static void IVInspectMethod(Method method,
                            NSString *prefix)
{
    if (!method)
        return;

    SEL selector =
        method_getName(method);

    const char *name =
        sel_getName(selector);

    const char *encoding =
        method_getTypeEncoding(method);

    IVLog(@"%@ METHOD: %s",
          prefix,
          name ? name : "(null)");

    IVLog(@"%@ ENCODING: %s",
          prefix,
          encoding ? encoding : "(null)");

    unsigned int count =
        method_getNumberOfArguments(method);

    IVLog(@"%@ ARGUMENT COUNT: %u",
          prefix,
          count);

    for (unsigned int i = 0; i < count; i++) {

        char type[256] = {0};

        method_getArgumentType(method,
                               i,
                               type,
                               sizeof(type));

        IVLog(@"%@ ARG %u: %s",
              prefix,
              i,
              type);
    }

    char returnType[256] = {0};

    method_getReturnType(method,
                         returnType,
                         sizeof(returnType));

    IVLog(@"%@ RETURN: %s",
          prefix,
          returnType);
}

/* =========================================================
   检查指定类中与 Request / Answer / Call 相关的方法
   ========================================================= */

static void IVInspectRelatedMethods(Class cls,
                                    NSString *label)
{
    if (!cls)
        return;

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    if (!methods) {
        IVLog(@"%@ : no methods", label);
        return;
    }

    IVLog(@"================================");
    IVLog(@"METHOD SCAN: %@", label);
    IVLog(@"Class: %s", class_getName(cls));
    IVLog(@"Total instance methods: %u", count);
    IVLog(@"================================");

    int found = 0;

    for (unsigned int i = 0; i < count; i++) {

        SEL selector =
            method_getName(methods[i]);

        const char *name =
            sel_getName(selector);

        if (!name)
            continue;

        NSString *methodName =
            [NSString stringWithUTF8String:name];

        NSString *lower =
            [methodName lowercaseString];

        BOOL related =
            [lower containsString:@"request"] ||
            [lower containsString:@"answer"] ||
            [lower containsString:@"call"] ||
            [lower containsString:@"action"];

        if (!related)
            continue;

        IVInspectMethod(methods[i],
                        @"");

        found++;

        /*
         * 限制输出数量，避免日志爆炸
         */
        if (found >= 100) {
            IVLog(@"Method scan limited to 100 entries");
            break;
        }
    }

    IVLog(@"Related methods found: %d",
          found);

    free(methods);
}

/* =========================================================
   检查继承关系
   ========================================================= */

static void IVInspectHierarchy(Class cls)
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

/* =========================================================
   安全检查 answerWithRequest:
   ========================================================= */

static void IVInspectAnswerWithRequest(Class cls)
{
    if (!cls)
        return;

    SEL selector =
        NSSelectorFromString(@"answerWithRequest:");

    Method method =
        class_getInstanceMethod(cls,
                                selector);

    IVLog(@"----- answerWithRequest: -----");

    if (!method) {
        IVLog(@"answerWithRequest: NOT FOUND");
        IVLog(@"------------------------------");
        return;
    }

    IVInspectMethod(method, @"");

    IVLog(@"------------------------------");
}

/* =========================================================
   安全检查指定类是否存在
   ========================================================= */

static void IVCheckClass(NSString *className)
{
    if (!className)
        return;

    Class cls =
        NSClassFromString(className);

    if (!cls) {
        IVLog(@"CLASS NOT FOUND: %@",
              className);
        return;
    }

    IVLog(@"================================");
    IVLog(@"CLASS FOUND: %@",
          className);
    IVLog(@"================================");

    IVInspectHierarchy(cls);

    IVInspectRelatedMethods(cls,
                            className);

    IVLog(@"================================");
}

/* =========================================================
   Runtime 枚举候选类
   ========================================================= */

static void IVScanRuntimeClasses(void)
{
    IVLog(@"================================");
    IVLog(@"RUNTIME CLASS SCAN START");
    IVLog(@"================================");

    int total =
        objc_getClassList(NULL, 0);

    if (total <= 0) {
        IVLog(@"objc_getClassList returned %d",
              total);
        return;
    }

    Class *classes =
        (__unsafe_unretained Class *)
        malloc(sizeof(Class) * total);

    if (!classes) {
        IVLog(@"Failed to allocate class list");
        return;
    }

    int actual =
        objc_getClassList(classes,
                          total);

    IVLog(@"Runtime classes: %d",
          actual);

    int found = 0;

    for (int i = 0; i < actual; i++) {

        Class cls = classes[i];

        if (!cls)
            continue;

        const char *name =
            class_getName(cls);

        if (!name)
            continue;

        NSString *className =
            [NSString stringWithUTF8String:name];

        NSString *lower =
            [className lowercaseString];

        /*
         * 只关注电话 / Request / Answer
         * 相关类。
         */
        BOOL related =
            [lower hasPrefix:@"tu"] ||
            [lower containsString:@"request"] ||
            [lower containsString:@"answer"];

        if (!related)
            continue;

        /*
         * 避免扫描大量无关 TU 类，
         * 只输出最相关的名字。
         */
        BOOL veryRelevant =
            [lower containsString:@"call"] ||
            [lower containsString:@"request"] ||
            [lower containsString:@"answer"];

        if (!veryRelevant)
            continue;

        IVLog(@"CANDIDATE CLASS: %@",
              className);

        found++;

        if (found >= 150) {
            IVLog(@"Runtime class output limited to 150");
            break;
        }
    }

    IVLog(@"Candidate classes found: %d",
          found);

    free(classes);

    IVLog(@"================================");
    IVLog(@"RUNTIME CLASS SCAN END");
    IVLog(@"================================");
}

/* =========================================================
   TUProxyCall 检查
   ========================================================= */

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

    if (strcmp(className,
               "TUProxyCall") != 0)
        return;

    IVLog(@"================================");
    IVLog(@"TUProxyCall DETECTED");
    IVLog(@"================================");

    IVLog(@"Class: %s",
          className);

    IVInspectHierarchy(cls);

    IVInspectAnswerWithRequest(cls);

    IVInspectRelatedMethods(cls,
                            @"TUProxyCall");

    /*
     * TUCall 父类
     */
    Class superClass =
        class_getSuperclass(cls);

    if (superClass) {

        IVLog(@"================================");
        IVLog(@"PARENT CLASS INSPECTION");
        IVLog(@"Class: %s",
              class_getName(superClass));

        IVInspectRelatedMethods(
            superClass,
            @"TUCall");

        IVLog(@"================================");
    }

    IVLog(@"================================");
    IVLog(@"SAFE INSPECTION FINISHED");
    IVLog(@"NO TUProxyCall METHODS INVOKED");
    IVLog(@"NO answerWithRequest: INVOKED");
    IVLog(@"NO delegate METHODS INVOKED");
    IVLog(@"================================");
}

/* =========================================================
   来电通知
   ========================================================= */

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

    if (strcmp(className,
               "TUProxyCall") != 0)
        return;

    IVLog(@"--------------------------------");

    IVLog(@"Notification: %@",
          notification.name);

    IVInspectTUProxyCall(object);

    IVLog(@"--------------------------------");
}

/* =========================================================
   初始化
   ========================================================= */

%ctor
{
    @autoreleasepool {

        NSString *process =
            [[NSProcessInfo processInfo]
             processName];

        /*
         * 只运行在 SpringBoard
         */
        if (![process isEqualToString:
                         @"SpringBoard"]) {

            return;
        }

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.8 LOADED");
        IVLog(@"Process: %@", process);
        IVLog(@"PID: %d", getpid());
        IVLog(@"================================");

        /*
         * 先检查几个已知类。
         *
         * 注意：
         * 这里只是 NSClassFromString，
         * 不调用任何实例方法。
         */

        IVCheckClass(@"TUCall");
        IVCheckClass(@"TUProxyCall");

        /*
         * 枚举当前进程已经注册的 Objective-C 类。
         */
        IVScanRuntimeClasses();

        /*
         * 监听电话状态变化。
         */
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

        IVLog(@"================================");
        IVLog(@"v1.8 SAFE RUNTIME INSPECTOR READY");
        IVLog(@"Monitoring TUProxyCall");
        IVLog(@"No call-control APIs invoked");
        IVLog(@"No answer request created");
        IVLog(@"================================");
    }
}

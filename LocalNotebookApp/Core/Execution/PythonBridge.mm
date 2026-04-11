#import "PythonBridge.h"

#include <Python.h>

@implementation PythonBridge

static BOOL sInitialized = NO;

+ (BOOL)appendPath:(NSString *)path toList:(PyWideStringList *)list error:(NSError * _Nullable __autoreleasing *)error {
    wchar_t *decoded = Py_DecodeLocale(path.UTF8String, NULL);
    if (decoded == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:16 userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode a Python module search path."}];
        }
        return NO;
    }
    PyStatus status = PyWideStringList_Append(list, decoded);
    PyMem_RawFree(decoded);
    if (PyStatus_Exception(status)) {
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:17 userInfo:@{NSLocalizedDescriptionKey: @"Unable to append a Python module search path."}];
        }
        return NO;
    }
    return YES;
}

+ (NSString *)pythonLibPathForResourcePath:(NSString *)resourcePath {
    NSString *libRoot = [resourcePath stringByAppendingPathComponent:@"python/lib"];
    NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:libRoot error:nil] ?: @[];
    for (NSString *entry in contents) {
        if ([entry hasPrefix:@"python3."]) {
            return [libRoot stringByAppendingPathComponent:entry];
        }
    }
    return [libRoot stringByAppendingPathComponent:@"python3.14"];
}

+ (NSString *)pythonErrorMessage {
    if (!PyErr_Occurred()) {
        return @"Unknown Python error.";
    }

    PyObject *ptype = NULL;
    PyObject *pvalue = NULL;
    PyObject *ptraceback = NULL;
    PyErr_Fetch(&ptype, &pvalue, &ptraceback);
    PyErr_NormalizeException(&ptype, &pvalue, &ptraceback);

    PyObject *tracebackModule = PyImport_ImportModule("traceback");
    PyObject *formatted = PyObject_CallMethod(tracebackModule, "format_exception", "OOO", ptype ?: Py_None, pvalue ?: Py_None, ptraceback ?: Py_None);
    PyObject *separator = PyUnicode_FromString("");
    PyObject *joined = PyUnicode_Join(separator, formatted);
    const char *utf8 = PyUnicode_AsUTF8(joined);
    NSString *message = utf8 ? [NSString stringWithUTF8String:utf8] : @"Python error";

    Py_XDECREF(joined);
    Py_XDECREF(separator);
    Py_XDECREF(formatted);
    Py_XDECREF(tracebackModule);
    Py_XDECREF(ptype);
    Py_XDECREF(pvalue);
    Py_XDECREF(ptraceback);
    return message;
}

+ (BOOL)initializeIfNeeded:(NSString *)resourcePath error:(NSError * _Nullable __autoreleasing *)error {
    if (sInitialized) {
        return YES;
    }

    NSString *pythonHome = [resourcePath stringByAppendingPathComponent:@"python"];
    NSString *pythonLib = [self pythonLibPathForResourcePath:resourcePath];
    NSString *dynload = [pythonLib stringByAppendingPathComponent:@"lib-dynload"];
    NSString *sitePackages = [pythonLib stringByAppendingPathComponent:@"site-packages"];
    NSString *appPath = [resourcePath stringByAppendingPathComponent:@"PythonApp"];

    PyStatus status;
    PyPreConfig preconfig;
    PyPreConfig_InitPythonConfig(&preconfig);
    preconfig.utf8_mode = 1;
    status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Py_PreInitialize failed."}];
        }
        return NO;
    }

    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 0;
    config.install_signal_handlers = 1;
    config.module_search_paths_set = 1;

    wchar_t *homeValue = Py_DecodeLocale(pythonHome.UTF8String, NULL);
    status = PyConfig_SetString(&config, &config.home, homeValue);
    PyMem_RawFree(homeValue);
    if (PyStatus_Exception(status)) {
        PyConfig_Clear(&config);
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:11 userInfo:@{NSLocalizedDescriptionKey: @"Unable to set PYTHONHOME."}];
        }
        return NO;
    }

    NSArray<NSString *> *paths = @[pythonLib, dynload, appPath, sitePackages];
    for (NSString *path in paths) {
        if (![self appendPath:path toList:&config.module_search_paths error:error]) {
            PyConfig_Clear(&config);
            return NO;
        }
    }

    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Py_InitializeFromConfig failed."}];
        }
        return NO;
    }

    PyRun_SimpleString("import sys\nsys.dont_write_bytecode = True\n");
    PyGILState_STATE state = PyGILState_Ensure();
    PyObject *module = PyImport_ImportModule("kernel_bridge");
    if (!module) {
        NSString *message = [self pythonErrorMessage];
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridge" code:13 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        PyGILState_Release(state);
        return NO;
    }
    Py_DECREF(module);
    PyGILState_Release(state);

    sInitialized = YES;
    return YES;
}

+ (NSDictionary<NSString *,id> * _Nullable)executeCode:(NSString *)code
                                             sessionID:(NSString *)sessionID
                                      workingDirectory:(NSString * _Nullable)workingDirectory
                                                 error:(NSError * _Nullable __autoreleasing *)error {
    PyGILState_STATE state = PyGILState_Ensure();
    PyObject *module = PyImport_ImportModule("kernel_bridge");
    PyObject *function = module ? PyObject_GetAttrString(module, "execute_code") : NULL;
    PyObject *args = PyTuple_New(3);
    PyTuple_SetItem(args, 0, PyUnicode_FromString(sessionID.UTF8String));
    PyTuple_SetItem(args, 1, PyUnicode_FromString(code.UTF8String));
    if (workingDirectory) {
        PyTuple_SetItem(args, 2, PyUnicode_FromString(workingDirectory.UTF8String));
    } else {
        Py_INCREF(Py_None);
        PyTuple_SetItem(args, 2, Py_None);
    }

    PyObject *result = function ? PyObject_CallObject(function, args) : NULL;
    NSDictionary *dictionary = nil;

    if (result) {
        const char *utf8 = PyUnicode_AsUTF8(result);
        NSString *jsonString = utf8 ? [NSString stringWithUTF8String:utf8] : @"{}";
        NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    } else if (error) {
        *error = [NSError errorWithDomain:@"PythonBridge" code:14 userInfo:@{NSLocalizedDescriptionKey: [self pythonErrorMessage]}];
    }

    Py_XDECREF(result);
    Py_XDECREF(args);
    Py_XDECREF(function);
    Py_XDECREF(module);
    PyGILState_Release(state);
    return dictionary;
}

+ (BOOL)restartSession:(NSString *)sessionID error:(NSError * _Nullable __autoreleasing *)error {
    PyGILState_STATE state = PyGILState_Ensure();
    PyObject *module = PyImport_ImportModule("kernel_bridge");
    PyObject *function = module ? PyObject_GetAttrString(module, "reset_session") : NULL;
    PyObject *result = function ? PyObject_CallFunction(function, "s", sessionID.UTF8String) : NULL;
    BOOL success = result != NULL;
    if (!success && error) {
        *error = [NSError errorWithDomain:@"PythonBridge" code:15 userInfo:@{NSLocalizedDescriptionKey: [self pythonErrorMessage]}];
    }
    Py_XDECREF(result);
    Py_XDECREF(function);
    Py_XDECREF(module);
    PyGILState_Release(state);
    return success;
}

+ (void)interrupt {
    PyErr_SetInterrupt();
}

@end

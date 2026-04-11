#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PythonBridge : NSObject

+ (BOOL)initializeIfNeeded:(NSString *)resourcePath error:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary<NSString *, id> * _Nullable)executeCode:(NSString *)code
                                              sessionID:(NSString *)sessionID
                                       workingDirectory:(NSString * _Nullable)workingDirectory
                                                  error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)restartSession:(NSString *)sessionID error:(NSError * _Nullable * _Nullable)error;
+ (void)interrupt;

@end

NS_ASSUME_NONNULL_END

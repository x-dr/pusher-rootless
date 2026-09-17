#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSString *NSPNotifyHubNormalizedWebhookURL(NSString *value);
NSString *NSPNotifyHubEventID(NSString *candidate, NSDate *occurredAt);
NSDictionary *NSPNotifyHubPayload(NSString *title, NSString *content,
                                  NSString *appName, NSString *appID,
                                  NSString *deviceName, NSDate *occurredAt);
NSURLSession *NSPNotifyHubSession(void);
BOOL NSPNotifyHubResponseIsAccepted(NSData *data, NSURLResponse *response,
                                    NSError *error,
                                    NSString **failureReason);

#ifdef __cplusplus
}
#endif

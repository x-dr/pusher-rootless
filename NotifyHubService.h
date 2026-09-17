#import <Foundation/Foundation.h>

NSString *NSPNotifyHubNormalizedWebhookURL(NSString *value);
NSString *NSPNotifyHubEventID(NSString *candidate, NSDate *occurredAt);
NSDictionary *NSPNotifyHubPayload(NSString *title, NSString *content,
                                  NSString *appName, NSString *appID,
                                  NSString *deviceName, NSDate *occurredAt);
NSURLSession *NSPNotifyHubSession(void);
BOOL NSPNotifyHubResponseIsAccepted(NSData *data, NSURLResponse *response,
                                    NSError *error,
                                    NSString **failureReason);

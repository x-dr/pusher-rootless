#import "NotifyHubService.h"
#import <CoreFoundation/CoreFoundation.h>

static const NSUInteger NSPNotifyHubMaximumResponseBytes = 1024 * 1024;

@interface NSPNotifyHubNoRedirectDelegate
    : NSObject <NSURLSessionTaskDelegate>
@end

@implementation NSPNotifyHubNoRedirectDelegate

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:
                 (void (^)(NSURLRequest *redirectRequest))completionHandler {
  completionHandler(nil);
}

@end

static NSString *NSPNotifyHubTruncatedString(NSString *value,
                                             NSUInteger maximumLength) {
  NSString *string = [value isKindOfClass:NSString.class] ? value : @"";
  if (maximumLength == 0) {
    return @"";
  }
  if (string.length <= maximumLength) {
    return string;
  }
  NSUInteger length = maximumLength;
  unichar lastCharacter = [string characterAtIndex:length - 1];
  if (CFStringIsSurrogateHighCharacter(lastCharacter) &&
      CFStringIsSurrogateLowCharacter([string characterAtIndex:length])) {
    length -= 1;
  }
  return [string substringToIndex:length];
}

NSString *NSPNotifyHubNormalizedWebhookURL(NSString *value) {
  if (![value isKindOfClass:NSString.class]) {
    return @"";
  }

  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
  NSString *scheme = components.scheme.lowercaseString;
  if (trimmed.length == 0 || trimmed.length > 2048 ||
      components.host.length == 0 ||
      (!([scheme isEqualToString:@"https"]) &&
      !([scheme isEqualToString:@"http"])) ||
      components.user.length > 0 || components.password.length > 0 ||
      components.query.length > 0 || components.fragment.length > 0) {
    return @"";
  }

  static NSRegularExpression *pathExpression = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    pathExpression = [[NSRegularExpression alloc]
        initWithPattern:@"^/api/v1/hooks/[0-9A-HJKMNP-TV-Z]{26}/?$"
                options:0
                  error:nil];
  });
  NSRange pathRange = NSMakeRange(0, components.path.length);
  if ([pathExpression firstMatchInString:components.path
                                 options:0
                                   range:pathRange] == nil) {
    return @"";
  }
  return trimmed;
}

NSString *NSPNotifyHubEventID(NSString *candidate, NSDate *occurredAt) {
  NSString *source = candidate;
  if ([candidate isKindOfClass:NSString.class] && candidate.length > 0 &&
      [occurredAt isKindOfClass:NSDate.class]) {
    long long occurredAtMilliseconds =
        (long long)(occurredAt.timeIntervalSince1970 * 1000.0);
    source = [NSString stringWithFormat:@"%@-%lld", candidate,
                                       occurredAtMilliseconds];
  }
  BOOL isPrintableASCII =
      [source isKindOfClass:NSString.class] && source.length > 0 &&
      source.length <= 120;
  if (isPrintableASCII) {
    for (NSUInteger index = 0; index < source.length; index++) {
      unichar character = [source characterAtIndex:index];
      if (character < 0x20 || character > 0x7e) {
        isPrintableASCII = NO;
        break;
      }
    }
  }

  NSString *identifier =
      isPrintableASCII ? source : NSUUID.UUID.UUIDString.lowercaseString;
  return [@"pusher-" stringByAppendingString:identifier];
}

NSDictionary *NSPNotifyHubPayload(NSString *title, NSString *content,
                                  NSString *appName, NSString *appID,
                                  NSString *deviceName, NSDate *occurredAt) {
  NSString *safeTitle = NSPNotifyHubTruncatedString(title, 200);
  NSString *safeContent = NSPNotifyHubTruncatedString(content, 10000);
  if (safeContent.length == 0) {
    safeContent = safeTitle.length > 0 ? safeTitle : @"收到一条 iOS 通知";
  }

  NSMutableDictionary *payload = [@{
    @"title" : safeTitle,
    @"content" : safeContent,
    @"level" : @"info",
    @"metadata" : @{
      @"appName" : appName ?: @"",
      @"appID" : appID ?: @"",
      @"deviceName" : deviceName ?: @""
    }
  } mutableCopy];
  if ([occurredAt isKindOfClass:NSDate.class]) {
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                              NSISO8601DateFormatWithFractionalSeconds;
    payload[@"occurredAt"] = [formatter stringFromDate:occurredAt];
    [formatter release];
  }
  return [payload autorelease];
}

NSURLSession *NSPNotifyHubSession(void) {
  static NSURLSession *session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPCookieStorage = nil;
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSPNotifyHubNoRedirectDelegate *delegate =
        [NSPNotifyHubNoRedirectDelegate new];
    session = [[NSURLSession sessionWithConfiguration:configuration
                                             delegate:delegate
                                        delegateQueue:nil] retain];
    [delegate release];
  });
  return session;
}

BOOL NSPNotifyHubResponseIsAccepted(NSData *data, NSURLResponse *response,
                                    NSError *error,
                                    NSString **failureReason) {
  if (error) {
    if (failureReason) {
      *failureReason = error.localizedDescription ?: @"网络请求失败";
    }
    return NO;
  }
  if (![response isKindOfClass:NSHTTPURLResponse.class]) {
    if (failureReason) {
      *failureReason = @"NotifyHub 未返回 HTTP 响应";
    }
    return NO;
  }

  NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
  if (statusCode != 202) {
    if (failureReason) {
      *failureReason =
          [NSString stringWithFormat:@"NotifyHub 返回 HTTP %ld，预期为 202",
                                     (long)statusCode];
    }
    return NO;
  }
  if (data.length == 0 || data.length > NSPNotifyHubMaximumResponseBytes) {
    if (failureReason) {
      *failureReason = data.length == 0 ? @"NotifyHub 返回空响应"
                                       : @"NotifyHub 响应超过 1 MiB";
    }
    return NO;
  }

  NSError *jsonError = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (jsonError || ![json isKindOfClass:NSDictionary.class] ||
      ![json[@"code"] isKindOfClass:NSNumber.class] ||
      ((NSNumber *)json[@"code"]).integerValue != 0 ||
      ![json[@"data"] isKindOfClass:NSDictionary.class]) {
    if (failureReason) {
      *failureReason = @"NotifyHub 未返回有效的成功响应";
    }
    return NO;
  }
  return YES;
}

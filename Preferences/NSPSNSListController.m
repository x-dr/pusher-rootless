#import "NSPSNSListController.h"
#import "NSPSharedSpecifiers.h"

static id getPreference(CFStringRef keyRef) {
  CFPropertyListRef val = CFPreferencesCopyValue(
      keyRef, PUSHER_APP_ID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
  return (__bridge id)val;
}

@implementation NSPSNSListController

- (NSArray *)specifiers {
  if (!_specifiers) {
    _specifiers = [[self loadSpecifiersFromPlistName:@"SNS"
                                              target:self] retain];
  }

  return _specifiers;
}

// runs after specifiers
- (void)viewDidLoad {
  [super viewDidLoad];

  _isService = (BOOL)[self.specifier propertyForKey:@"service"];
  if (_isService) {
    _service = [[self.specifier propertyForKey:@"service"] retain];
    _isCustomService =
        [self.specifier propertyForKey:@"isCustomService"] &&
        ((NSNumber *)[self.specifier propertyForKey:@"isCustomService"])
            .boolValue;

    // synchronized if all values are nil
    BOOL synchronizedWithGlobal = YES;
    for (PSSpecifier *specifier in self.specifiers) {
      [specifier setProperty:_service forKey:@"service"];
      [specifier setProperty:[specifier propertyForKey:@"key"]
                      forKey:@"globalKey"];
      if (!_isCustomService) {
        [specifier setProperty:XStr(@"%@%@", _service,
                                    [specifier propertyForKey:@"key"])
                        forKey:@"key"];
      }
      // if finds value that is truthy, not all are synchronized globally
      if (synchronizedWithGlobal) {
        BOOL foundTruthy = NO;
        if (_isCustomService) {
          NSDictionary *customServices =
              getPreference(
                  (__bridge CFStringRef)NSPPreferenceCustomServicesKey)
                  ?: @{};
          if (customServices[_service]) {
            foundTruthy =
                customServices[_service][[specifier propertyForKey:@"key"]] !=
                nil;
          }
        } else {
          foundTruthy =
              getPreference(
                  (__bridge CFStringRef)[specifier propertyForKey:@"key"]) !=
              nil;
        }
        synchronizedWithGlobal = !foundTruthy;
      }
    }

    PSSpecifier *synchronizedGroup = [PSSpecifier emptyGroupSpecifier];
    [synchronizedGroup
        setProperty:@"将所有值与全局偏好同步。修改任意设置都会覆盖全局偏好；"
                    @"重新同步会移除覆盖，并再次跟随全局偏好。"
             forKey:@"footerText"];

    _synchronizeSpecifier =
        [PSSpecifier preferenceSpecifierNamed:(synchronizedWithGlobal
                                                   ? @"已同步"
                                                   : @"与全局设置同步")
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    [_synchronizeSpecifier setButtonAction:@selector(synchronizeWithGlobal:)];
    [_synchronizeSpecifier setProperty:@(!synchronizedWithGlobal)
                                forKey:@"enabled"];

    [self insertSpecifier:synchronizedGroup atIndex:0];
    [self insertSpecifier:_synchronizeSpecifier atIndex:1];
  }
}

- (void)synchronizeWithGlobal:(PSSpecifier *)specifier {
  for (PSSpecifier *spec in self.specifiers) {
    if ([spec propertyForKey:@"key"]) { // only if has key because group
                                        // specifiers dont matter for example
      [spec performSetterWithValue:nil];
      [self reloadSpecifier:spec animated:YES];
    }
  }
  [specifier setName:@"已同步"];
  [specifier setProperty:@NO forKey:@"enabled"];
  [self reloadSpecifier:specifier animated:YES];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
  if (!_isService) {
    [super setPreferenceValue:value specifier:specifier];
  }
  if (value && [specifier.identifier
                   containsString:@"SufficientNotificationSettingsIsAnd"]) {
    // 兼容汉化后的 label，同时保留旧英文 ID 的读取路径。
    PSSpecifier *allowNotificationsSpecifier =
        [self specifierForID:@"允许通知"];
    if (!allowNotificationsSpecifier) {
      allowNotificationsSpecifier = [self specifierForID:@"Allow Notifications"];
    }
    if (allowNotificationsSpecifier) {
      [allowNotificationsSpecifier performSetterWithValue:value];
      [self reloadSpecifier:allowNotificationsSpecifier animated:YES];
    }
    if (!((NSNumber *)value).boolValue) {
      PSSpecifier *requireANWithORSpecifier =
          [self specifierForID:@"OR 时要求允许通知"];
      if (!requireANWithORSpecifier) {
        requireANWithORSpecifier =
            [self specifierForID:@"Require Allow Notifications with OR"];
      }
      if (requireANWithORSpecifier) {
        [requireANWithORSpecifier performSetterWithValue:@YES];
        [self reloadSpecifier:requireANWithORSpecifier animated:YES];
      }
    }
  }
  if (!_isService) {
    return;
  }
  // enable synchronize button if we change a value
  if (_synchronizeSpecifier) {
    [_synchronizeSpecifier setName:@"与全局设置同步"];
    [_synchronizeSpecifier setProperty:@YES forKey:@"enabled"];
    [self reloadSpecifier:_synchronizeSpecifier animated:YES];
  }
  if (_isCustomService) {
    [NSPSharedSpecifiers setPreferenceValue:value forCustomSpecifier:specifier];
  } else {
    [NSPSharedSpecifiers setPreferenceValue:value
                 forBuiltInServiceSpecifier:specifier];
  }
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
  if (!_isService) {
    return [super readPreferenceValue:specifier];
  }
  if (_isCustomService) {
    return [NSPSharedSpecifiers readCustomPreferenceValue:specifier];
  } else {
    return [NSPSharedSpecifiers readBuiltInServicePreferenceValue:specifier];
  }
}

@end

#import "NSPServiceListController.h"
#import "NSPServiceController.h"

static void setPreference(CFStringRef keyRef, CFPropertyListRef val,
                          BOOL shouldNotify) {
  CFPreferencesSetValue(keyRef, val, PUSHER_APP_ID, kCFPreferencesCurrentUser,
                        kCFPreferencesAnyHost);
  CFPreferencesSynchronize(PUSHER_APP_ID, kCFPreferencesCurrentUser,
                           kCFPreferencesAnyHost);
  if (shouldNotify) {
    // Reload stuff
    notify_post(PUSHER_PREFS_NOTIFICATION);
  }
}

static NSString *const NSPServiceSectionEnabled = @"已启用";
static NSString *const NSPServiceSectionDisabled = @"已停用";
static NSString *const NSPServicePreferenceEnabledKey = @"Enabled";

static NSString *displayNameForService(NSString *service) {
  if (XEq(service, PUSHER_SERVICE_FEISHU)) {
    return @"飞书";
  }
  if (XEq(service, PUSHER_SERVICE_WECHAT)) {
    return @"企业微信";
  }
  return service;
}

@implementation NSPServiceListController

- (void)dealloc {
  [_serviceImages release];
  [_prefs release];
  [_table release];
  [_sections release];
  [_data release];
  [super dealloc];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  _lastTargetService = nil;
  _lastTargetIndexPath = nil;

  _loadedServiceControllers = [NSMutableDictionary new];

  CGRect tableFrame = self.view.bounds;
  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPad) {
    tableFrame = self.rootController.view.bounds;
  }
  _table = [[UITableView alloc] initWithFrame:tableFrame
                                        style:UITableViewStyleGrouped];
  [_table registerClass:UITableViewCell.class
      forCellReuseIdentifier:@"ServiceCell"];
  _table.dataSource = self;
  _table.delegate = self;
  _table.allowsSelectionDuringEditing = YES;
  [self.view addSubview:_table];
  _addNewServiceBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:@"添加"
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(addNewService)];

  self.navigationItem.title = @"服务";
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:@"编辑"
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(toggleEditing:)];
  self.navigationItem.leftBarButtonItem = nil;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [NSPusherManager.sharedController setActiveTintColor:nil];
  [self tintUIToPusherColor];

  // Get preferences
  CFArrayRef keyList = CFPreferencesCopyKeyList(
      PUSHER_APP_ID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
  _prefs = @{};
  if (keyList) {
    _prefs = (NSDictionary *)CFPreferencesCopyMultiple(
        keyList, PUSHER_APP_ID, kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    if (!_prefs) {
      _prefs = @{};
    }
    CFRelease(keyList);
  }

  // 分组标题是中文显示名；偏好中的 Enabled 键仍保留英文以兼容旧数据。
  _sections =
      [@[ NSPServiceSectionEnabled, NSPServiceSectionDisabled ] retain];
  _data = [@{
    NSPServiceSectionEnabled : [NSMutableArray new],
    NSPServiceSectionDisabled : [NSMutableArray new]
  } mutableCopy];
  _services = [BUILTIN_PUSHER_SERVICES retain];
  _customServices = [(NSDictionary *)(_prefs[NSPPreferenceCustomServicesKey]
                                          ?: @{}) mutableCopy];

  _defaultImage = [DEFAULT_IMAGE retain];
  _serviceImages = [[NSMutableDictionary new] retain];

  for (NSString *service in _services) {
    NSString *enabledKey = XStr(@"%@Enabled", service);
    if (_prefs[enabledKey] && ((NSNumber *)_prefs[enabledKey]).boolValue) {
      [_data[NSPServiceSectionEnabled] addObject:service];
    } else {
      [_data[NSPServiceSectionDisabled] addObject:service];
    }
    _serviceImages[service] =
        [UIImage imageNamed:XStr(@"BuiltInService_%@", service)
                   inBundle:PUSHER_BUNDLE]
            ?: _defaultImage;
  }

  // make deep mutable and preload service images
  for (NSString *customService in _customServices.allKeys) {
    _customServices[customService] =
        [(_customServices[customService] ?: @{}) mutableCopy];
    NSNumber *enabled =
        _customServices[customService][NSPServicePreferenceEnabledKey];
    if (_customServices[customService] &&
        enabled && enabled.boolValue) {
      [_data[NSPServiceSectionEnabled] addObject:customService];
    } else {
      [_data[NSPServiceSectionDisabled] addObject:customService];
    }
    _serviceImages[customService] =
        [UIImage imageNamed:XStr(@"CustomService_%@", customService)
                   inBundle:PUSHER_BUNDLE]
            ?: _defaultImage;
  }

  [_data[NSPServiceSectionEnabled]
      sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  [_data[NSPServiceSectionDisabled]
      sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

  [_table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (!_prefs[@"ServiceListTutorialShown"] ||
      !((NSNumber *)_prefs[@"ServiceListTutorialShown"]).boolValue) {
    [self showTutorial];
  }
}

- (void)showTutorial {
  UIWindow *window = nil;
  NSSet *scenes = [UIApplication sharedApplication].connectedScenes;
  for (UIScene *scene in scenes) {
      if (scene.activationState == UISceneActivationStateForegroundActive) {
          UIWindowScene *windowScene = (UIWindowScene *)scene;
          for (UIWindow *win in windowScene.windows) {
              if (win.isKeyWindow) {
                  window = win;
                  break;
              }
          }
          if (window != nil) {
              break;
          }
      }
  }
  // for (UIWindow *win in [UIApplication sharedApplication].windows) {
  //     if (win.isKeyWindow) {
  //         window = win;
  //         break;
  //     }
  // }
  // UIWindow *window = [UIApplication sharedApplication].keyWindow;
  UIView *tutorialView = [[UIView alloc] initWithFrame:window.bounds];
  tutorialView.alpha = 0.f;
  tutorialView.backgroundColor = [UIColor colorWithWhite:0.f alpha:0.9f];

  // Label setup
  UILabel *label = [UILabel new];
  label.font = [UIFont fontWithName:@"HelveticaNeue-Thin"
                               size:UIFont.systemFontSize * 1.5f];
  label.textColor = UIColor.whiteColor;
  label.text =
      @"设置好服务后，记得点击右上角“编辑”，并把要启用的服务拖到顶部的"
      @"“已启用”分组。\n\n轻点任意位置继续。";
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.numberOfLines = 0;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.textAlignment = NSTextAlignmentCenter;
  [tutorialView addSubview:label];

  // Constraints
  [label addConstraint:[NSLayoutConstraint
                           constraintWithItem:label
                                    attribute:NSLayoutAttributeWidth
                                    relatedBy:NSLayoutRelationEqual
                                       toItem:nil
                                    attribute:NSLayoutAttributeNotAnAttribute
                                   multiplier:1
                                     constant:270]];
  [label addConstraint:[NSLayoutConstraint
                           constraintWithItem:label
                                    attribute:NSLayoutAttributeHeight
                                    relatedBy:NSLayoutRelationEqual
                                       toItem:nil
                                    attribute:NSLayoutAttributeNotAnAttribute
                                   multiplier:1
                                     constant:tutorialView.frame.size.height]];
  [label.centerXAnchor constraintEqualToAnchor:label.superview.centerXAnchor]
      .active = YES;
  [label.centerYAnchor constraintEqualToAnchor:label.superview.centerYAnchor]
      .active = YES;

  [window addSubview:tutorialView];
  [UIView animateWithDuration:0.3
                   animations:^{
                     tutorialView.alpha = 1.f;
                   }];

  // Add touch action after a second
  UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(dismissTutorial:)];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.f * NSEC_PER_SEC),
                 dispatch_get_main_queue(), ^{
                   // Dismiss gesture
                   [tutorialView addGestureRecognizer:tapGestureRecognizer];
                 });

  CFStringRef tutorialKeyRef = CFSTR("ServiceListTutorialShown");
  setPreference(tutorialKeyRef, (__bridge CFNumberRef) @YES, NO);
  CFRelease(tutorialKeyRef);
  NSMutableDictionary *mutablePrefs = [_prefs mutableCopy];
  mutablePrefs[@"ServiceListTutorialShown"] = @YES;
  _prefs = [mutablePrefs copy];
}

- (void)dismissTutorial:(UITapGestureRecognizer *)tapGestureRecognizer {
  UIView *tutorialView = tapGestureRecognizer.view;
  [UIView animateWithDuration:0.3
      animations:^{
        tutorialView.alpha = 0.f;
      }
      completion:^(BOOL finished) {
        [tutorialView removeFromSuperview];
      }];
}

- (void)toggleEditing:(UIBarButtonItem *)barButtonItem {
  [_table setEditing:![_table isEditing] animated:YES];
  barButtonItem.title = [_table isEditing] ? @"完成" : @"编辑";
  self.navigationItem.leftBarButtonItem =
      [_table isEditing] ? _addNewServiceBarButtonItem : nil;
  if (![_table isEditing]) {
    // Save
    for (NSString *service in _services) {
      NSString *enabledKey = XStr(@"%@Enabled", service);
      setPreference((__bridge CFStringRef)enabledKey,
                    (__bridge CFNumberRef)
                        @([_data[NSPServiceSectionEnabled]
                            containsObject:service]),
                    NO);
    }
    for (NSString *customService in _customServices.allKeys) {
      NSNumber *customServiceEnabled =
          @([_data[NSPServiceSectionEnabled] containsObject:customService]);
      if (!_customServices[customService]) {
        _customServices[customService] =
            [@{NSPServicePreferenceEnabledKey : customServiceEnabled}
                mutableCopy];
      } else {
        _customServices[customService][NSPServicePreferenceEnabledKey] =
            customServiceEnabled;
      }
    }
    [self saveCustomServices]; // will notify post
                               // notify_post(PUSHER_PREFS_NOTIFICATION);
  }
}

- (void)addNewService {
  UIAlertController *alert = XAlertTitle(@"添加自定义服务", nil);
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = @"服务名称";
  }];
  [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  id handler = ^(UIAlertAction *action) {
    if (!alert || !alert.textFields ||
        ![alert.textFields isKindOfClass:NSArray.class]) {
      XLog(@"alert or alert.textFields nil: %@ %@", alert,
           alert ? alert.textFields : nil);
      return;
    }
    if (alert.textFields.count == 0) {
      XLog(@"No text fields found");
      return;
    }
    UITextField *textField = alert.textFields[0];
    if (!textField || !textField.text ||
        ![textField.text isKindOfClass:NSString.class]) {
      XLog(@"textField or textField.text nil: %@ %@", textField,
           textField ? textField.text : nil);
      return;
    }
    NSString *newServiceName = [[textField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]]
        retain];
    if (newServiceName.length < 1) {
      XLog(@"newServiceName empty");
      return;
    }
    if ([_customServices.allKeys containsObject:newServiceName] ||
        [_services containsObject:newServiceName]) {
      id existsHandler = ^(UIAlertAction *existsAction) {
        [self addNewService];
      };
      UIAlertController *existsAlert =
          XAlertTitle(@"错误", @"已存在同名服务。");
      [existsAlert addAction:XAlertBtnHandler(@"好", existsHandler)];
      [self presentViewController:existsAlert animated:YES completion:nil];
      XLog(@"newServiceName already exists");
      return;
    }
    _customServices[newServiceName] =
        [@{NSPServicePreferenceEnabledKey : @NO} mutableCopy];
    [_data[NSPServiceSectionDisabled] addObject:newServiceName];
    [_data[NSPServiceSectionDisabled]
        sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    UIImage *defaultImage = _defaultImage;
    if (!defaultImage || ![defaultImage isKindOfClass:UIImage.class]) {
      defaultImage = DEFAULT_IMAGE;
    }

    NSString *imageName = XStr(@"CustomService_%@", newServiceName);
    _serviceImages[newServiceName] =
        [UIImage imageNamed:imageName inBundle:PUSHER_BUNDLE] ?: defaultImage;
    [_table reloadSections:[NSIndexSet indexSetWithIndex:1]
          withRowAnimation:UITableViewRowAnimationAutomatic];
    [self saveCustomServices];
  };
  [alert addAction:XAlertBtnHandler(@"添加", handler)];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCustomServices {
  setPreference((__bridge CFStringRef)NSPPreferenceCustomServicesKey,
                (__bridge CFPropertyListRef)_customServices, YES);
}

- (void)tableView:(UITableView *)table
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [table deselectRowAtIndexPath:indexPath animated:YES];
  NSString *currService = _data[_sections[indexPath.section]][indexPath.row];
  BOOL isCustomService = [_customServices.allKeys containsObject:currService];
  if (table.editing) {
    if (isCustomService) {
      // Rename
      [self renameService:currService];
    }
  } else {
    NSPServiceController *controller;
    if ([_loadedServiceControllers.allKeys containsObject:currService]) {
      controller = _loadedServiceControllers[currService];
    } else {
      controller = [[NSPServiceController alloc]
          initWithService:currService
                    image:_serviceImages[currService]
                 isCustom:isCustomService];
      _loadedServiceControllers[currService] = controller;
    }
    [self pushController:controller];
  }
}

- (NSInteger)tableView:(UITableView *)table
    numberOfRowsInSection:(NSInteger)section {
  return ((NSArray *)_data[_sections[section]]).count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
  return _sections.count;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForHeaderInSection:(NSInteger)section {
  return _sections[section];
}

- (BOOL)tableView:(UITableView *)tableView
    shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
  return NO;
}

- (UITableViewCell *)tableView:(UITableView *)table
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell =
      [table dequeueReusableCellWithIdentifier:@"ServiceCell"
                                  forIndexPath:indexPath];
  NSString *service = _data[_sections[indexPath.section]][indexPath.row];
  cell.textLabel.text = displayNameForService(service);
  cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  cell.imageView.image = _serviceImages[service];
  return cell;
}

- (BOOL)tableView:(UITableView *)table
    canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
  return YES;
}

- (void)tableView:(UITableView *)table
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
  _lastTargetService = nil;
  _lastTargetIndexPath = nil;
  NSString *service =
      _data[_sections[sourceIndexPath.section]][sourceIndexPath.row];
  [_data[_sections[sourceIndexPath.section]]
      removeObjectAtIndex:sourceIndexPath.row];
  [_data[_sections[destinationIndexPath.section]]
      insertObject:service
           atIndex:destinationIndexPath.row];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *service = _data[_sections[indexPath.section]][indexPath.row];
  if ([_customServices.allKeys containsObject:service]) {
    return UITableViewCellEditingStyleDelete;
  }
  return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)table
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *service = _data[_sections[indexPath.section]][indexPath.row];
  if (editingStyle == UITableViewCellEditingStyleDelete &&
      [_customServices.allKeys containsObject:service]) {
    [_customServices removeObjectForKey:service];
    [_data[_sections[indexPath.section]] removeObjectAtIndex:indexPath.row];
    [self saveCustomServices];

    [table deleteRowsAtIndexPaths:@[ indexPath ]
                 withRowAnimation:UITableViewRowAnimationLeft];
  }
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                         toProposedIndexPath:
                             (NSIndexPath *)proposedDestinationIndexPath {
  if (sourceIndexPath.section == proposedDestinationIndexPath.section) {
    return sourceIndexPath;
  }
  NSString *service =
      _data[_sections[sourceIndexPath.section]][sourceIndexPath.row];
  if (_lastTargetService && XEq(service, _lastTargetService)) {
    return _lastTargetIndexPath;
  }
  _lastTargetService = service;
  NSArray *tempArray =
      [[_data
        [_sections
         [proposedDestinationIndexPath
              .section]] arrayByAddingObject : service] sortedArrayUsingSelector :
       @selector(localizedCaseInsensitiveCompare:)];
  _lastTargetIndexPath =
      [NSIndexPath indexPathForRow:[tempArray indexOfObject:service]
                         inSection:proposedDestinationIndexPath.section];
  return _lastTargetIndexPath;
}

- (void)renameService:(NSString *)currService {

  UIAlertController *alert =
      XAlertTitle(XStr(@"重命名 %@", currService), nil);
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = @"服务名称";
    textField.text = currService;
  }];
  [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  id handler = ^(UIAlertAction *action) {
    UITextField *textField = alert.textFields[0];
    if (!textField || !textField.text) {
      return;
    }
    NSString *newServiceName = [textField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (newServiceName.length < 1 || XEq(newServiceName, currService)) {
      return;
    }
    if ([_customServices.allKeys containsObject:newServiceName] ||
        [_services containsObject:newServiceName]) {
      id existsHandler = ^(UIAlertAction *existsAction) {
        [self renameService:currService];
      };
      UIAlertController *existsAlert =
          XAlertTitle(XStr(@"重命名 %@", currService), @"已存在同名服务。");
      [existsAlert addAction:XAlertBtnHandler(@"好", existsHandler)];
      [self presentViewController:existsAlert animated:YES completion:nil];
      return;
    }

    _serviceImages[newServiceName] = _serviceImages[currService];
    [_serviceImages removeObjectForKey:currService];

    _customServices[newServiceName] =
        [_customServices[currService] mutableCopy];
    [_customServices removeObjectForKey:currService];
    [self saveCustomServices];

    // Get preferences
    CFArrayRef keyList = CFPreferencesCopyKeyList(
        PUSHER_APP_ID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSMutableDictionary *newPrefs = [NSMutableDictionary new];
    if (keyList) {
      newPrefs = [(NSDictionary *)CFPreferencesCopyMultiple(
          keyList, PUSHER_APP_ID, kCFPreferencesCurrentUser,
          kCFPreferencesAnyHost) mutableCopy];
      if (!newPrefs) {
        newPrefs = [NSMutableDictionary new];
      }
      CFRelease(keyList);
    }

    NSDictionary *keysToMigrate = @{
      NSPPreferenceCustomServiceCustomAppsKey(currService) :
          NSPPreferenceCustomServiceCustomAppsKey(newServiceName)
    };

    NSDictionary *prefixesToMigrate = @{
      NSPPreferenceCustomServiceBLPrefix(currService) :
          NSPPreferenceCustomServiceBLPrefix(newServiceName)
    };

    NSMutableArray *keysToRemove =
        [NSMutableArray arrayWithArray:keysToMigrate.allKeys];

    for (NSString *oldKey in keysToMigrate.allKeys) {
      NSString *newKey = keysToMigrate[oldKey];
      newPrefs[newKey] = [newPrefs[oldKey] copy];
      [newPrefs removeObjectForKey:oldKey];
    }

    for (NSString *oldPrefix in prefixesToMigrate.allKeys) {
      NSString *newPrefix = prefixesToMigrate[oldPrefix];
      NSMutableArray *foundPrefixKeys = [NSMutableArray new];
      for (id key in newPrefs.allKeys) {
        if (![key isKindOfClass:NSString.class]) {
          continue;
        }
        if ([key hasPrefix:oldPrefix]) {
          [foundPrefixKeys addObject:key];
        }
      }
      for (NSString *oldKey in foundPrefixKeys) {
        NSString *newKey =
            [oldKey stringByReplacingOccurrencesOfString:oldPrefix
                                              withString:newPrefix];
        newPrefs[newKey] = [newPrefs[oldKey] copy];
        [newPrefs removeObjectForKey:oldKey];
        [keysToRemove addObject:oldKey];
      }
    }

    CFPreferencesSetMultiple((__bridge CFDictionaryRef)newPrefs,
                             (__bridge CFArrayRef)keysToRemove, PUSHER_APP_ID,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(PUSHER_PREFS_NOTIFICATION);

    NSString *currSection =
        ((NSNumber *)_customServices[newServiceName]
                     [NSPServicePreferenceEnabledKey])
                .boolValue
            ? NSPServiceSectionEnabled
            : NSPServiceSectionDisabled;
    [_data[currSection] removeObject:currService];
    [_data[currSection] addObject:newServiceName];
    [_data[currSection]
        sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    [_table reloadSections:[NSIndexSet
                               indexSetWithIndexesInRange:NSMakeRange(0, 2)]
          withRowAnimation:UITableViewRowAnimationFade];
  };
  [alert addAction:XAlertBtnHandler(@"重命名", handler)];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  [self.view endEditing:YES];
}

@end

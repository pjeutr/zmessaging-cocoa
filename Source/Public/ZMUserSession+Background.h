// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
// 


#import <zmessaging/ZMUserSession.h>

@import UIKit;

@interface ZMUserSession (ZMBackground)

/// Store deviceToken
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

/// Remove deviceToken
- (void)removeRemoteNotificationTokenIfNeeded;

/// Process the payload of the remote notification. This may cause a @c UILocalNotification to be displayed.
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;

/// Process the local notifications.
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification;

/// Notifies the receiver about callbacks from a local notification.
- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification responseInfo:(NSDictionary *)responseInfo completionHandler:(void(^)())completionHandler;

/// Causes the user session to update its state from the backend.
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;

/// Lets the user session process event for a background URL session it has set up.
- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler;

/// Lets the user session process local and remote notifications contained in the launch options;
- (void)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;

/// Calls registerUserNotificationSettings on application
- (void)setupPushNotificationsForApplication:(UIApplication *)application;

- (void)applicationDidEnterBackground:(NSNotification *)note;
- (void)applicationWillEnterForeground:(NSNotification *)note;

@end

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


#import "ZMUserSessionTestsBase.h"
#import "ZMUserSession+Authentication.h"
#import "ZMAuthenticationStatus+Testing.h"

@interface ZMUserSessionAuthenticationTests : ZMUserSessionTestsBase

@end

@implementation ZMUserSessionAuthenticationTests



- (void)testThatIfWeHaveNoCookieAndNoCredentialsAuthFailedGetsCalled;
{
    // expect
    __block BOOL correctQueue = YES;
    [self verifyMockLater:self.authenticationObserver];
    [[(id) self.authenticationObserver expect] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(id arg){
        correctQueue = correctQueue && ([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
        NSError *error = arg;
        return (error.userSessionErrorCode == ZMUserSessionNeedsCredentials);
    }]];
    
    // when
    [self.sut start];
    
    // then
    XCTAssertFalse(self.sut.isLoggedIn);
    XCTAssertTrue(correctQueue);
}

- (void)simulateAuthenticatedStatus
{
    [self.cookieStorage setAuthenticationCookieData:self.validCookie];
    [self.uiMOC setPersistentStoreMetadata:@"foo" forKey:ZMPersistedClientIdKey];
    [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = [NSUUID createUUID];
    [self.syncMOC saveOrRollback];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatStartFiresLoginSuccessIfTheStatusIsAuthenticated
{
    // given
    [self simulateAuthenticatedStatus];
    
    // expectations
    [[(id) self.authenticationObserver expect] authenticationDidSucceed];
    id result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:YES];
    [[[self.transportSession stub] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [self verifyMockLater:self.authenticationObserver];
    
    // when
    [self.sut start];
    
    // then
    XCTAssertTrue(self.sut.isLoggedIn);
}

- (void)testThatItDoesNotReset_RegisteredOnThisDevice_IfItAlreadyHasACookie
{
    // given
    [self simulateAuthenticatedStatus];
    self.sut.authenticationStatus.registeredOnThisDevice = YES;
    
    // expectations
    [[(id) self.authenticationObserver expect] authenticationDidSucceed];
    id result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:YES];
    [[[self.transportSession stub] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [self verifyMockLater:self.authenticationObserver];
    
    // when
    XCTAssertTrue(self.sut.authenticationStatus.registeredOnThisDevice);
    [self.sut start];
}

- (void)testThatNotifiesThatRequestsAreAvailableIfStartingWithACookieAndTheClientIsRegistered
{
    // given
    [self simulateAuthenticatedStatus];
    
    // expectations
    [[(id) self.authenticationObserver stub] authenticationDidSucceed];
    [[self.operationLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"anything@example.com" password:@"123456"];
    [self.sut loginWithCredentials:cred];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertTrue(self.sut.isLoggedIn);
    [self.operationLoop stopMocking];
}

- (void)testThatNotifiesThatRequestsAreAvailableIfRegisteringClient
{
    // given
    [self.uiMOC setPersistentStoreMetadata:nil forKey:ZMPersistedClientIdKey]; //need to register client
    [self.cookieStorage setAuthenticationCookieData:self.validCookie];
    
    // expectations
    [[(id) self.authenticationObserver stub] authenticationDidSucceed];
    [[self.operationLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"anything@example.com" password:@"123456"];
    [self.sut loginWithCredentials:cred];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(self.sut.isLoggedIn);
    XCTAssertEqualObjects(self.sut.authenticationStatus.loginCredentials, cred);
    [self.operationLoop stopMocking];
}


- (void)testThatItNotifiesTheUIWhenLoggingInWithAnEmptyPassword;
{
    // given
    NSError *expectedError = [NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil];
    
    // expectations
    [[(id) self.authenticationObserver reject] authenticationDidSucceed];
    [[(id) self.authenticationObserver expect] authenticationDidFail:expectedError];
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"anything@example.com" password:@""];
    [self.sut loginWithCredentials:cred];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(self.sut.isLoggedIn);
    XCTAssertNil(self.sut.authenticationStatus.loginCredentials);
}

- (void)testThatLoginWithEmailFiresLoginSuccessIfItHasCookie
{
    // given
    [self.cookieStorage setAuthenticationCookieData:self.validCookie];
    
    // expectations
    ZMTransportEnqueueResult *r = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:YES];
    [[[self.transportSession stub] andReturn:r] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
//    [[(id) self.authenticationObserver expect] authenticationDidSucceed];
//    [self verifyMockLater:self.authenticationObserver];
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"someone@example.com" password:@"valid-password"];
    [self.sut loginWithCredentials:cred];
    
    // then
//    XCTAssertTrue(self.sut.isLoggedIn);
    XCTAssertTrue(self.sut.authenticationStatus.currentPhase == ZMAuthenticationPhaseAuthenticated);
}

- (void)testThatAuthenticationFailedGetsCalledIfGettingAnAccessTokenFailed
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication failed"];
    [[[(id) self.authenticationObserver expect] andDo:^(NSInvocation *inv ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidFail:OCMOCK_ANY];
    
    // when
    self.authFailHandler(nil);
    
    // then
    [self verifyMockLater:self.authenticationObserver];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertFalse(self.sut.isLoggedIn);
}

- (void)testThatItClears_RegisteredOnThisDevice_WhenTryingToLogIn
{
    // given
    self.sut.authenticationStatus.registeredOnThisDevice = YES;
    ZMCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+49123456789" verificationCode:@"123456"];
    
    // when
    [self.sut loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(self.sut.authenticationStatus.registeredOnThisDevice);
}

- (void)testThatItSetsLoginCredentialsWithPhone
{
    // given
    ZMCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+49123456789" verificationCode:@"123456"];
    
    // expect
    [[self.operationLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self.sut loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.loginCredentials, credentials);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseLoginWithPhone);
    [self.operationLoop stopMocking];
}

- (void)testThatItSetsLoginCredentialsWithEmail
{
    // given
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"dsg$#%24"];
    
    // expect
    [[self.operationLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self.sut loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.loginCredentials, credentials);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    [self.operationLoop stopMocking];
}

- (void)testThatItRequestsLoginValidationCode
{
    // given
    NSString *phone = @"+4912345678900";
    
    // expect
    [[self.operationLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self.sut requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.loginPhoneNumberThatNeedsAValidationCode, phone);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin);
    [self.operationLoop stopMocking];
}

- (void)testThatItResetsPushTokensIfNecessary
{
    // given
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:[NSData data] identifier:@"token" transportType:@"someType" fallback:nil isRegistered:YES];
    ZMPushToken *pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:[NSData data] identifier:@"token" transportType:@"someType" fallback:@"APNS" isRegistered:YES];
    
    self.uiMOC.pushToken = pushToken;
    self.uiMOC.pushKitToken = pushKitToken;

    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"dsg$#%24"];
    
    XCTAssertTrue(self.uiMOC.pushToken.isRegistered);
    XCTAssertTrue(self.uiMOC.pushKitToken.isRegistered);

    [[self.operationLoop stub] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self.sut loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(self.uiMOC.pushToken.isRegistered);
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
    XCTAssertEqualObjects(self.uiMOC.pushToken, pushToken);
    XCTAssertEqualObjects(self.uiMOC.pushKitToken, pushKitToken);
}

@end

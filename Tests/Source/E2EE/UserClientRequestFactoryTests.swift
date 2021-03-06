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


import zmessaging
import ZMUtilities
import ZMTesting
import Cryptobox
import ZMCMockTransport
import ZMCDataModel

// used by tests to fake errors on genrating pre keys
public class FakeKeysStore: UserClientKeysStore {

    var failToGeneratePreKeys: Bool = false
    var failToGenerateLastPreKey: Bool = false
    
    var lastGeneratedKeys : (keys: [CBPreKey], minIndex: UInt, maxIndex: UInt) = ([],0,0)
    var lastGeneratedLastPrekey : CBPreKey?
    
    override public func generateMoreKeys(count: UInt, start: UInt) throws -> ([CBPreKey], UInt, UInt) {
        if self.failToGeneratePreKeys {
            let error = NSError(domain: "cryptobox.error", code: 0, userInfo: ["reason" : "using fake store with simulated fail"])
            throw error
        }
        else {
            let keys = try! super.generateMoreKeys(count, start: start)
            lastGeneratedKeys = keys
            return keys
        }
    }
    
    override public func lastPreKey() throws -> CBPreKey {
        if self.failToGenerateLastPreKey {
            let error = NSError(domain: "cryptobox.error", code: 0, userInfo: ["reason" : "using fake store with simulated fail"])
            throw error
        }
        else {
            lastGeneratedLastPrekey = try! super.lastPreKey()
            return lastGeneratedLastPrekey!
        }
    }
    
}

class UserClientRequestFactoryTests: MessagingTest {
    
    var sut: UserClientRequestFactory!
    var authenticationStatus: ZMAuthenticationStatus!
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        authenticationStatus = ZMMockAuthenticationStatus(managedObjectContext: self.syncMOC, cookie: nil);
        self.sut = UserClientRequestFactory()
        
        let newKeyStore = FakeKeysStore()
        self.syncMOC.userInfo.setObject(newKeyStore, forKey: "ZMUserClientKeysStore")
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func expectedKeyPayloadForClientPreKeys(client : UserClient) -> [NSDictionary] {
        let generatedKeys = (client.keysStore as! FakeKeysStore).lastGeneratedKeys
        let expectedPrekeys = generatedKeys.keys.enumerate().map {
            return ["key": $1.data!.base64String(), "id": Int(generatedKeys.minIndex) + $0]
        }
        return expectedPrekeys
    }
    
    func testThatItCreatesRegistrationRequestWithEmailCorrectly() {
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        let credentials = ZMEmailCredentials(email: "some@example.com", password: "123")
        
        //when
        let request = try! sut.registerClientRequest(client, credentials: credentials, authenticationStatus:authenticationStatus)
        
        //then        
        AssertOptionalNotNil(request.transportRequest, "Should return non nil request") { request in
            AssertOptionalNotNil(request.payload.asDictionary() as? [String: NSObject], "Request should contain payload") { payload in
                
                AssertDictionaryHasOptionalValue(payload, key: "type", expected: ZMUserClientTypePermanent, "Client type should be 'permanent'")
                AssertDictionaryHasOptionalValue(payload, key: "password", expected: credentials.password!, "Payload should contain password")
                
                let lastPreKey = (client.keysStore as! FakeKeysStore).lastGeneratedLastPrekey!
                let expectedLastPreKeyPayload = ["key": lastPreKey.data!.base64String(), "id": CBMaxPreKeyID+1]
                
                AssertDictionaryHasOptionalValue(payload, key: "lastkey", expected: expectedLastPreKeyPayload, "Payload should contain last prekey")
                
                let preKeysPayloadData = payload["prekeys"] as? [[NSString: AnyObject]]
                AssertOptionalNotNil(preKeysPayloadData, "Payload should contain prekeys") {preKeysPayloadData in
                    XCTAssertEqual(preKeysPayloadData, self.expectedKeyPayloadForClientPreKeys(client))
                }
                
                AssertOptionalNotNil(payload["sigkeys"] as? [String: NSObject], "Payload should contain apns keys") { apnsKeysPayload in
                    XCTAssertNotNil(apnsKeysPayload["enckey"], "Payload should contain apns enc key")
                    XCTAssertNotNil(apnsKeysPayload["mackey"], "Payload should contain apns mac key")
                }
            }
        }
    }
    
    func testThatItCreatesRegistrationRequestWithPhoneCredentialsCorrectly() {
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        
        //when
        let request : ZMUpstreamRequest
        do {
            request = try sut.registerClientRequest(client, credentials: nil, authenticationStatus:authenticationStatus)
        }
        catch {
            XCTFail("error should be nil")
            return
        }
        
        //then
        
        AssertOptionalNotNil(request.transportRequest, "Should return non nil request") { request in
            
            XCTAssertEqual(request.path, "/clients", "Should create request with correct path")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST, "Should create POST request")
            
            AssertOptionalNotNil(request.payload.asDictionary() as? [String: NSObject], "Request should contain payload") { payload in
                
                AssertDictionaryHasOptionalValue(payload, key: "type", expected: ZMUserClientTypePermanent, "Client type should be 'permanent'")
                XCTAssertNil(payload["password"])
                
                let lastPreKey = try! client.keysStore.lastPreKey()
                let expectedLastPreKeyPayload = ["key": lastPreKey.data!.base64String(), "id": CBMaxPreKeyID+1]
                
                AssertDictionaryHasOptionalValue(payload, key: "lastkey", expected: expectedLastPreKeyPayload, "Payload should contain last prekey")
                
                let preKeysPayloadData = payload["prekeys"] as? [[NSString: AnyObject]]
                AssertOptionalNotNil(preKeysPayloadData, "Payload should contain prekeys") {preKeysPayloadData in
                    XCTAssertEqual(preKeysPayloadData, self.expectedKeyPayloadForClientPreKeys(client))
                }
                
                AssertOptionalNotNil(payload["sigkeys"] as? [String: NSObject], "Payload should contain apns keys") { apnsKeysPayload in
                    XCTAssertNotNil(apnsKeysPayload["enckey"], "Payload should contain apns enc key")
                    XCTAssertNotNil(apnsKeysPayload["mackey"], "Payload should contain apns mac key")
                }
            }
        }
    }
    
    func testThatItReturnsNilForRegisterClientRequestIfCanNotGeneratePreKyes() {
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        (client.keysStore as! FakeKeysStore).failToGeneratePreKeys = true
        
        let credentials = ZMEmailCredentials(email: "some@example.com", password: "123")

        //when
        let request = try? sut.registerClientRequest(client, credentials: credentials, authenticationStatus:authenticationStatus)

        XCTAssertNil(request, "Should not return request if client fails to generate prekeys")
    }
    
    func testThatItReturnsNilForRegisterClientRequestIfCanNotGenerateLastPreKey() {
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        (client.keysStore as! FakeKeysStore).failToGenerateLastPreKey = true

        let credentials = ZMEmailCredentials(email: "some@example.com", password: "123")
        
        //when
        let request = try? sut.registerClientRequest(client, credentials: credentials, authenticationStatus:authenticationStatus)
        
        XCTAssertNil(request, "Should not return request if client fails to generate last prekey")
    }
    
    func testThatItCreatesUpdateClientRequestCorrectlyWhenStartingFromPrekey0() {
        
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        
        //when
        let request = try! sut.updateClientPreKeysRequest(client)
        
        AssertOptionalNotNil(request.transportRequest, "Should return non nil request") { request in
            
            XCTAssertEqual(request.path, "/clients/\(client.remoteIdentifier)", "Should create request with correct path")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPUT, "Should create POST request")
            
            AssertOptionalNotNil(request.payload.asDictionary() as? [String: NSObject], "Request should contain payload") { payload in
                
                let preKeysPayloadData = payload["prekeys"] as? [[NSString: AnyObject]]
                AssertOptionalNotNil(preKeysPayloadData, "Payload should contain prekeys") {preKeysPayloadData in
                    XCTAssertEqual(preKeysPayloadData, self.expectedKeyPayloadForClientPreKeys(client))
                }
            }
        }
    }
    
    func testThatItCreatesUpdateClientRequestCorrectlyWhenStartingFromPrekey400() {
        
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        client.preKeysRangeMax = 400
        
        //when
        let request = try! sut.updateClientPreKeysRequest(client)
        
        AssertOptionalNotNil(request.transportRequest, "Should return non nil request") { request in
            
            XCTAssertEqual(request.path, "/clients/\(client.remoteIdentifier)", "Should create request with correct path")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPUT, "Should create POST request")
            
            AssertOptionalNotNil(request.payload.asDictionary() as? [String: NSObject], "Request should contain payload") { payload in
                
                let preKeysPayloadData = payload["prekeys"] as? [[NSString: AnyObject]]
                AssertOptionalNotNil(preKeysPayloadData, "Payload should contain prekeys") {preKeysPayloadData in
                    XCTAssertEqual(preKeysPayloadData, self.expectedKeyPayloadForClientPreKeys(client))
                }
            }
        }
    }

    
    func testThatItReturnsNilForUpdateClientRequestIfCanNotGeneratePreKeys() {
        
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        (client.keysStore as! FakeKeysStore).failToGeneratePreKeys = true

        client.remoteIdentifier = NSUUID.createUUID().transportString()
        
        //when
        let request = try? sut.updateClientPreKeysRequest(client)
        
        XCTAssertNil(request, "Should not return request if client fails to generate prekeys")
    }
    
    func testThatItDoesNotReturnRequestIfClientIsNotSynced() {
        //given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        
        // when
        do {
            _ = try sut.updateClientPreKeysRequest(client)
        }
        catch let error as NSError {
            XCTAssertNotNil(error, "Should not return request if client does not have remoteIdentifier")
        }
        
    }
    
    func testThatItCreatesARequestToDeleteAClient() {
        
        // given
        let email = "foo@example.com"
        let password = "gfsgdfgdfgdfgdfg"
        let credentials = ZMEmailCredentials(email: email, password: password)
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        client.remoteIdentifier = "\(client.objectID)"
        self.syncMOC.saveOrRollback()
        
        // when
        let nextRequest = sut.deleteClientRequest(client, credentials: credentials)
        
        // then
        AssertOptionalNotNil(nextRequest) {
            XCTAssertEqual($0.transportRequest.path, "/clients/\(client.remoteIdentifier)")
            XCTAssertEqual($0.transportRequest.payload as! [String:String], [
                "email" : email,
                "password" : password
                ])
            XCTAssertEqual($0.transportRequest.method, ZMTransportRequestMethod.MethodDELETE)
        }
    }
    
    func testThatItCreatesMissingClientsRequest() {
        
        // given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        
        let missingUser = ZMUser.insertNewObjectInManagedObjectContext(self.syncMOC)
        missingUser.remoteIdentifier = NSUUID.createUUID()
        
        let firstMissingClient = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        firstMissingClient.remoteIdentifier = NSString.createAlphanumericalString()
        firstMissingClient.user = missingUser
        
        let secondMissingClient = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        secondMissingClient.remoteIdentifier = NSString.createAlphanumericalString()
        secondMissingClient.user = missingUser

        // when
        client.missesClient(firstMissingClient)
        client.missesClient(secondMissingClient)
        
        let map = MissingClientsMap(Array(client.missingClients!), pageSize: sut.missingClientsUserPageSize)
        let request = sut.fetchMissingClientKeysRequest(map)
        _ = [missingUser.remoteIdentifier!.transportString(): [firstMissingClient.remoteIdentifier, secondMissingClient.remoteIdentifier]]
        
        // then
        AssertOptionalNotNil(request, "Should create request to fetch clients' keys") {request in
            XCTAssertEqual(request.transportRequest.method, ZMTransportRequestMethod.MethodPOST)
            XCTAssertEqual(request.transportRequest.path, "/users/prekeys")
            let userPayload = request.transportRequest.payload.asDictionary()[missingUser.remoteIdentifier!.transportString()] as? NSArray
            AssertOptionalNotNil(userPayload, "Clients map should contain missid user id") {userPayload in
                XCTAssertTrue(userPayload.containsObject(firstMissingClient.remoteIdentifier), "Clients map should contain all missed clients id for each user")
                XCTAssertTrue(userPayload.containsObject(secondMissingClient.remoteIdentifier), "Clients map should contain all missed clients id for each user")
            }
        }
    }
}

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


import Foundation
import ZMCSystem
import ZMTransport
import ZMUtilities
import Cryptobox
import ZMCDataModel

private let zmLog = ZMSLog(tag: "Crypto")


// Register new client, update it with new keys, deletes clients.
@objc
public class UserClientRequestStrategy: ZMObjectSyncStrategy, ZMObjectStrategy, ZMUpstreamTranscoder, ZMSingleRequestTranscoder {
    
    weak var clientRegistrationStatus: ZMClientRegistrationStatus?
    weak var authenticationStatus: ZMAuthenticationStatus?
    weak var clientUpdateStatus: ClientUpdateStatus?

    private(set) var modifiedSync: ZMUpstreamModifiedObjectSync! = nil
    private(set) var deleteSync: ZMUpstreamModifiedObjectSync! = nil
    private(set) var insertSync: ZMUpstreamInsertedObjectSync! = nil
    private(set) var fetchAllClientsSync: ZMSingleRequestSync! = nil
    private var didRetryRegisteringSignalingKeys : Bool = false
    
    public var requestsFactory: UserClientRequestFactory = UserClientRequestFactory()
    public var minNumberOfRemainingKeys: UInt = 20
    
    private(set) var userClientsObserverToken: NSObjectProtocol!
    private(set) var userClientsSync: ZMRemoteIdentifierObjectSync!
    
    private var insertSyncFilter: NSPredicate {
        return NSPredicate { [unowned self] object, _ -> Bool in
            guard let client = object as? UserClient else { return false }
            return client.user == ZMUser.selfUserInContext(self.managedObjectContext)
        }
    }
    
    public init(authenticationStatus:ZMAuthenticationStatus,
                clientRegistrationStatus:ZMClientRegistrationStatus,
                clientUpdateStatus:ClientUpdateStatus,
                context: NSManagedObjectContext)
    {
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        self.clientUpdateStatus = clientUpdateStatus
        
        super.init(managedObjectContext: context)
        
        let deletePredicate = NSPredicate(format: "\(ZMUserClientMarkedToDeleteKey) == YES")
        let modifiedPredicate = self.modifiedPredicate()

        self.modifiedSync = ZMUpstreamModifiedObjectSync(transcoder: self, entityName: UserClient.entityName(), updatePredicate: modifiedPredicate, filter: nil, keysToSync: [ZMUserClientNumberOfKeysRemainingKey, ZMUserClientMissingKey, ZMUserClientNeedsToUpdateSignalingKeysKey], managedObjectContext: context)
        self.deleteSync = ZMUpstreamModifiedObjectSync(transcoder: self, entityName: UserClient.entityName(), updatePredicate: deletePredicate, filter: nil, keysToSync: [ZMUserClientMarkedToDeleteKey], managedObjectContext: context)
        self.insertSync = ZMUpstreamInsertedObjectSync(transcoder: self, entityName: UserClient.entityName(), filter: insertSyncFilter, managedObjectContext: context)
        
        self.fetchAllClientsSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: context)
        
        self.userClientsSync = ZMRemoteIdentifierObjectSync(transcoder: self, managedObjectContext: self.managedObjectContext)
        
        self.userClientsObserverToken = NSNotificationCenter.defaultCenter().addObserverForName(ZMNeedsToUpdateUserClientsNotificationName, object: nil, queue: .mainQueue()) { [unowned self] note in

            let objectID = note.userInfo?[ZMNeedsToUpdateUserClientsNotificationUserObjectIDKey] as? NSManagedObjectID
            self.managedObjectContext.performGroupedBlock {
                guard let optionalUser = try? objectID.flatMap(self.managedObjectContext.existingObjectWithID), user = optionalUser as? ZMUser  else { return }
                self.userClientsSync.setRemoteIdentifiersAsNeedingDownload(Set(arrayLiteral: user.remoteIdentifier!))
                ZMOperationLoop.notifyNewRequestsAvailable(self)
            }
        }
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self.userClientsObserverToken)
    }
    
    func modifiedPredicate() -> NSPredicate {
        let notDeletedPredicate = NSPredicate(format: "\(ZMUserClientMarkedToDeleteKey) == NO")
        
        let baseModifiedPredicate = UserClient.predicateForObjectsThatNeedToBeUpdatedUpstream()
        let needToUploadKeysPredicate = NSPredicate(format: "\(ZMUserClientNumberOfKeysRemainingKey) < \(minNumberOfRemainingKeys)")
        let needsToUploadSignalingKeysPredicate = NSPredicate(format: "\(ZMUserClientNeedsToUpdateSignalingKeysKey) == YES")
        let missingClientsPredicate = NSPredicate(format: "\(ZMUserClientMissingKey).@count > 0")
        let remoteIdentifierPresentPredicate = NSPredicate(format: "\(ZMUserClientRemoteIdentifierKey) != nil")
        
        let modifiedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[
            baseModifiedPredicate,
            notDeletedPredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates:[needToUploadKeysPredicate, missingClientsPredicate, needsToUploadSignalingKeysPredicate]),
            remoteIdentifierPresentPredicate
            ])
        return modifiedPredicate
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard let clientRegistrationStatus = self.clientRegistrationStatus,
            let clientUpdateStatus = self.clientUpdateStatus else {
                return nil
        }
        
        if clientRegistrationStatus.currentPhase == .WaitingForLogin {
            return nil
        }
        
        if clientUpdateStatus.currentPhase == .FetchingClients {
            fetchAllClientsSync.readyForNextRequestIfNotBusy()
            return fetchAllClientsSync.nextRequest()
        }
        
        if clientUpdateStatus.currentPhase == .DeletingClients && clientUpdateStatus.credentials != nil {
            if let request =  deleteSync.nextRequest() {
                return request
            }
        }
        
        if clientRegistrationStatus.currentPhase == .Unregistered {
            if let request = insertSync.nextRequest() {
                return request
            }
        }
        
        if let request = modifiedSync.nextRequest() {
            return request
        }
        
        return userClientsSync.nextRequest()
    }
    
    //we don;t use this method but it's required by ZMObjectStrategy protocol
    public var requestGenerators: [ZMRequestGenerator] {
        return []
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.insertSync, self.modifiedSync, self.deleteSync]
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
        
    public func requestForSingleRequestSync(sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        return requestsFactory.fetchClientsRequest()
    }
    
    public func shouldCreateRequestToSyncObject(managedObject: ZMManagedObject, forKeys keys: Set<String>, withSync sync: AnyObject) -> Bool {
        guard let sync = sync as? ZMUpstreamModifiedObjectSync where sync == self.modifiedSync
        else { return true }
        
        var keysToSync = keys
        if keys.contains(ZMUserClientMissingKey),
            let client = managedObject as? UserClient where (client.missingClients == nil || client.missingClients?.count == 0)
        {
            keysToSync.remove(ZMUserClientMissingKey)
            client.resetLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
            self.modifiedSync.objectsDidChange(Set(arrayLiteral: client))
        }
        return (keysToSync.count > 0)
    }
    
    public func requestForUpdatingObject(managedObject: ZMManagedObject, forKeys keys: Set<NSObject>) -> ZMUpstreamRequest? {
        if let managedObject = managedObject as? UserClient {
            guard let clientUpdateStatus = self.clientUpdateStatus else { fatal("clientUpdateStatus is not set") }
            
            var request: ZMUpstreamRequest!
            
            switch keys {
            case _ where keys.contains(ZMUserClientNumberOfKeysRemainingKey):
                do {
                    try request = requestsFactory.updateClientPreKeysRequest(managedObject)
                } catch let e {
                    fatal("Couldn't create request for new pre keys: \(e)")
                }
            case _ where keys.contains(ZMUserClientMarkedToDeleteKey):
                if clientUpdateStatus.currentPhase == ClientUpdatePhase.DeletingClients && clientUpdateStatus.credentials != nil {
                    request = requestsFactory.deleteClientRequest(managedObject, credentials: clientUpdateStatus.credentials!)
                }
                else {
                    fatal("No email credentials in memory")
                }
            case _ where keys.contains(ZMUserClientNeedsToUpdateSignalingKeysKey):
                do {
                    try request = requestsFactory.updateClientSignalingKeysRequest(managedObject)
                } catch let e {
                    fatal("Couldn't create request for new signaling keys: \(e)")
                }
            case _ where keys.contains(ZMUserClientMissingKey):
                if let missing = managedObject.missingClients where missing.count > 0 {
                    let map = MissingClientsMap(Array(missing), pageSize: requestsFactory.missingClientsUserPageSize)
                    request = requestsFactory.fetchMissingClientKeysRequest(map)
                }

            default: fatal("Unknown keys to sync (\(keys))")
            }
            
            return request
        }
        else {
            fatal("Called requestForUpdatingObject() on \(managedObject) to sync keys: \(keys)")
        }
    }
    
    public func requestForInsertingObject(managedObject: ZMManagedObject, forKeys keys: Set<NSObject>?) -> ZMUpstreamRequest? {
        if let managedObject = managedObject as? UserClient {
            guard let authenticationStatus = self.authenticationStatus else { fatal("authenticationStatus is not set") }
            let request = try? requestsFactory.registerClientRequest(managedObject, credentials: clientRegistrationStatus?.emailCredentials, authenticationStatus: authenticationStatus)
            return request
        }
        else {
            fatal("Called requestForInsertingObject() on \(managedObject)")
        }
    }
    
    public func shouldRetryToSyncAfterFailedToUpdateObject(managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse: Set<NSObject>) -> Bool {
        if keysToParse.contains(ZMUserClientNumberOfKeysRemainingKey) {
            return false
        }
        if keysToParse.contains(ZMUserClientNeedsToUpdateSignalingKeysKey) {
            if response.HTTPStatus == 400, let label = response.payloadLabel() where label == "bad-request" {
                // Malformed prekeys uploaded - recreate and retry once per launch

                if didRetryRegisteringSignalingKeys {
                    (managedObject as? UserClient)?.needsToUploadSignalingKeys = false
                    managedObjectContext.saveOrRollback()
                    fatal("UserClientTranscoder sigKey request failed with bad-request - \(upstreamRequest.debugDescription)")
                }
                didRetryRegisteringSignalingKeys = true
                return true
            }
            (managedObject as? UserClient)?.needsToUploadSignalingKeys = false
            return false
        }
        else if keysToParse.contains(ZMUserClientMarkedToDeleteKey) {
            let error = self.errorFromFailedDeleteResponse(response)
            if error.code == ClientUpdateError.ClientToDeleteNotFound.rawValue {
                self.managedObjectContext.deleteObject(managedObject)
                self.managedObjectContext.saveOrRollback()
            }
            clientUpdateStatus?.failedToDeleteClient(managedObject as! UserClient, error: error)
            return false
        }
        else {
            //first we try to register without password (credentials can be there, but they can not contain password)
            //if there is no password in credentials but it's required, we will recieve error from backend and only then will ask for password
            let error = self.errorFromFailedInsertResponse(response)
            if error.code == Int(ZMUserSessionErrorCode.CanNotRegisterMoreClients.rawValue) {
                clientUpdateStatus?.needsToFetchClients(andVerifySelfClient: false)
            }
            clientRegistrationStatus?.didFailToRegisterClient(error)
            return true;
        }
    }
    
    public func updateInsertedObject(managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        if let client = managedObject as? UserClient {
            
            guard
                let payload = response.payload.asDictionary() as? [String : AnyObject],
                let remoteIdentifier = payload["id"] as? String
            else {
                zmLog.warn("Unexpected backend response for inserted client")
                return
            }
            
            client.remoteIdentifier = remoteIdentifier
            client.numberOfKeysRemaining = Int32(requestsFactory.keyCount)
            UserClient.createOrUpdateClient(payload, context: self.managedObjectContext)
            clientRegistrationStatus?.didRegisterClient(client)
        }
        else {
            fatal("Called updateInsertedObject() on \(managedObject)")
        }
    }
    
    public func errorFromFailedDeleteResponse(response: ZMTransportResponse!) -> NSError {
        var errorCode: ClientUpdateError = .None
        if let response = response where response.result == .PermanentError {
            if let errorLabel = response.payload.asDictionary()["label"] as? String {
                switch errorLabel {
                case "client-not-found":
                    errorCode = .ClientToDeleteNotFound
                    break
                case "invalid-credentials":
                    errorCode = .InvalidCredentials
                    break
                default:
                    break
                }
            }
        }
        return ClientUpdateError.errorForType(errorCode)()
    }
    
    public func errorFromFailedInsertResponse(response: ZMTransportResponse!) -> NSError {
        var errorCode: ZMUserSessionErrorCode = .UnkownError
        if let response = response where response.result == .PermanentError {

            if let errorLabel = response.payload.asDictionary()["label"] as? String {
                switch errorLabel {
                case "missing-auth":
                    let selfUserHasEmail = (ZMUser.selfUserInContext(self.managedObjectContext).emailAddress != nil )
                    errorCode = selfUserHasEmail ? .NeedsPasswordToRegisterClient : .NeedsToRegisterEmailToRegisterClient
                    break
                case "too-many-clients":
                    errorCode = .CanNotRegisterMoreClients
                    break
                case "invalid-credentials":
                    errorCode = .InvalidCredentials
                    break
                default:
                    break
                }
            }
        }
        return NSError(domain: ZMUserSessionErrorDomain, code: Int(errorCode.rawValue), userInfo: nil)
    }
    
    public func didReceiveResponse(response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        
        switch (response.result) {
        case .Success:
            if let payload = response.payload.asArray() as? [[String: AnyObject]] {
                func createSelfUserClient(clientInfo: [String: AnyObject]) -> UserClient? {
                    let client = UserClient.createOrUpdateClient(clientInfo, context: self.managedObjectContext)
                    client?.user = ZMUser.selfUserInContext(self.managedObjectContext)
                    return client
                }
                
                let clients = payload.map(createSelfUserClient).filter { $0 != nil }
                let unwrappedClients = clients.map{$0!}
                self.managedObjectContext.saveOrRollback()
                clientUpdateStatus?.didFetchClients(unwrappedClients)
            }
            break
        case .Expired:
            clientUpdateStatus?.failedToFetchClients()
            break
        default:
            break
        }
    }
    
    /// Returns whether synchronization of this object needs additional requests
    public func updateUpdatedObject(managedObject: ZMManagedObject, requestUserInfo: [NSObject : AnyObject]?, response: ZMTransportResponse, keysToParse: Set<NSObject>) -> Bool {
        
        if keysToParse.contains(ZMUserClientMissingKey) {
            return processResponseForUpdatingMissingClients(managedObject, requestUserInfo: requestUserInfo, responsePayload: response.payload)
        }
        else if keysToParse.contains(ZMUserClientMarkedToDeleteKey) {
            return processResponseForDeletingClients(managedObject, requestUserInfo: requestUserInfo, responsePayload: response.payload)
        }
        else if keysToParse.contains(ZMUserClientNumberOfKeysRemainingKey) {
            (managedObject as! UserClient).numberOfKeysRemaining += Int32(requestsFactory.keyCount)
        }
        else if keysToParse.contains(ZMUserClientNeedsToUpdateSignalingKeysKey) {
            didRetryRegisteringSignalingKeys = false
        }
        
        return false
    }
    
    /// Make sure that we don't block messages or continue requesting messages for a client that can not be fetched
    private func clearMissingMessagesBecauseClientCanNotBeFeched(client: UserClient, selfClient: UserClient) {
        client.failedToEstablishSession = true
        cleanMessagesMissingRecipient(client)
        selfClient.removeMissingClient(client)
    }

    /** 
    Creates session and update missing clients and messages that depend on those clients
    */
    private func establishSessionAndUpdateMissingClients(clientId: String,
        prekeyString: String,
        selfClient: UserClient,
        missingClient: UserClient?) {
            guard let missingClient = missingClient else { return }
            
            let sessionCreated = selfClient.establishSessionWithClient(missingClient, usingPreKey: prekeyString)
            // If the session creation failed, the client probably has corrupted prekeys,
            // we mark the client in order to send him a bogus message and not block all requests
            missingClient.failedToEstablishSession = !sessionCreated
            
            cleanMessagesMissingRecipient(missingClient)
            selfClient.removeMissingClient(missingClient)
    }
    
    /// Process a client entry in a response to a missed clients (prekeys) request
    private func processPrekeyEntry(clientId: String, prekeyData: Any?, selfClient: UserClient, missingClient: UserClient) {
        if let prekeyDictionary = prekeyData as? [String : AnyObject],
            let prekeyString = prekeyDictionary["key"] as? String
        {
            self.establishSessionAndUpdateMissingClients(
                clientId,
                prekeyString: prekeyString,
                selfClient: selfClient,
                missingClient:missingClient)
        }
        else {
            self.clearMissingMessagesBecauseClientCanNotBeFeched(missingClient, selfClient: selfClient)
        }
    }
    
    /// - returns: a lookup table for missing client by remote client ID
    private func missingUserClientIdToUserClientMap(selfClient: UserClient) -> [String : UserClient] {
        var missedClientIdsToClientsMap = [String : UserClient]()
        guard let missingClients = selfClient.missingClients else {
            return missedClientIdsToClientsMap
        }
        for missingClient in missingClients {
            missedClientIdsToClientsMap[missingClient.remoteIdentifier] = missingClient
        }
        return missedClientIdsToClientsMap
    }
    
    /** 
    Processes a response to a request to fetch missing client
    The response will contain clientid and prekeys in the following format:
     
         {
            <userId> : {
                <clientId> : {
                    key : <index>
                    id : <prekey>
                },
                <clientId> : {
                    key : <index>
                    id : <prekey>
                },
                ...
            }
            <userId> : {
                <clientId> : null   // this will happen in case the
                                    // client was deleted just before we requested it
            }
         }
    */
    private func processResponseForUpdatingMissingClients(
        managedObject: ZMManagedObject!,
        requestUserInfo: [NSObject : AnyObject]!,
        responsePayload payload: ZMTransportData!) -> Bool {
        
        guard let dictionary = payload.asDictionary() as? [String : [String : AnyObject]],
              let selfClient = ZMUser.selfUserInContext(self.managedObjectContext).selfClient()
        else {
            zmLog.error("Response payload for client-keys is not a valid [String : [String : AnyObject]]")
            return false
        }
        
        let missedClientLookupByRemoteIdentifier = self.missingUserClientIdToUserClientMap(selfClient)

        /// client IDs that are still remaining to download. Will be updated (removed) as we discover more clients in the payload
        var remainingClientsIds = Set((requestUserInfo[MissingClientsRequestUserInfoKeys.clients] as! [String]).filter {
            missedClientLookupByRemoteIdentifier[$0] != nil // I will not consider the clients that are not missing anymore
                                                            // as still to download
        })
        let originalRemainingClientsCount = remainingClientsIds.count
            
        /// for each user ID
        for (userIdString, clients) in dictionary {
            guard let _ = NSUUID.uuidWithTransportString(userIdString) else {
                zmLog.error("\(userIdString) is not a valid UUID")
                continue
            }
            
            /// for each client ID
            for (clientId, prekeyData) in clients {
                remainingClientsIds.remove(clientId)
                
                guard let missedClient = missedClientLookupByRemoteIdentifier[clientId] else {
                    /// If the client id is not missing (anymore), we should not do anything.
                    /// maybe a previous request solved it, or it was deleted by a push, or...
                    continue
                }
                self.processPrekeyEntry(clientId, prekeyData: prekeyData, selfClient: selfClient, missingClient: missedClient)
            }
        }
        
        // check if this request actually changed something. If not, it means that the requested client ids
        // are deleted on the BE side and we should ignore them
        
        let remainingClientsCountDidNotChange = remainingClientsIds.count == originalRemainingClientsCount
        if remainingClientsCountDidNotChange {
            for clientId in remainingClientsIds {
                if let client = missedClientLookupByRemoteIdentifier[clientId] {
                    self.clearMissingMessagesBecauseClientCanNotBeFeched(client, selfClient: selfClient)
                }
            }
        }
        return selfClient.missingClients?.count > 0 // we are done
    }
    
    private func expireMessagesMissingRecipient(client: UserClient) {
        if let messagesMissingRecipient = client.messagesMissingRecipient {
            for message in messagesMissingRecipient {
                message.expire()
            }
        }
    }
    
    private func cleanMessagesMissingRecipient(client: UserClient) {
        if let messagesMissingRecipient = client.messagesMissingRecipient {
            for message in messagesMissingRecipient {
                if let message = message as? ZMOTRMessage {
                    message.doesNotMissRecipient(client)
                }
                else {
                    client.mutableSetValueForKey("messagesMissingRecipient").removeObject(message)
                }
            }
        }
    }
    
    func processResponseForDeletingClients(managedObject: ZMManagedObject!, requestUserInfo: [NSObject : AnyObject]!, responsePayload payload: ZMTransportData!) -> Bool {
        //is it safe for ui??
        if let client = managedObject as? UserClient {
            managedObject.managedObjectContext?.performGroupedBlock({ () -> Void in
                // end session and delete client
                client.deleteClientAndEndSession()
                // notify the clientStatus
                self.clientUpdateStatus?.didDeleteClient()
            })
        }
        return false
    }
    
    // Should return the objects that need to be refetched from the BE in case of upload error
    public func objectToRefetchForFailedUpdateOfObject(managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public var isSlowSyncDone: Bool {
        return true
    }
    
    public func setNeedsSlowSync() {
        //no op
    }
    
    public func processEvents(events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        events.forEach(processUpdateEvent)
    }
            
    private func processUpdateEvent(event: ZMUpdateEvent) {
        if event.type != .UserClientAdd && event.type != .UserClientRemove {
            return
        }
        guard let clientInfo = event.payload["client"] as? [String: AnyObject] else {
            zmLog.error("Client info has unexpected payload")
            return
        }
        
        let selfUser = ZMUser.selfUserInContext(self.managedObjectContext)
        
        switch event.type {
        case .UserClientAdd:
            if let client = UserClient.createOrUpdateClient(clientInfo, context: self.managedObjectContext) {
                client.user = selfUser
                selfUser.selfClient()?.addNewClientToIgnored(client, causedBy: .None)
            }
        case .UserClientRemove:
            let selfClientId = selfUser.selfClient()?.remoteIdentifier
            guard let clientId = clientInfo["id"] as? String else { return }

            if selfClientId != clientId {
                if let clientToDelete = selfUser.clients.filter({ $0.remoteIdentifier == clientId }).first {
                    clientToDelete.deleteClientAndEndSession()
                }
            } else {
                clientRegistrationStatus?.didDetectCurrentClientDeletion()
            }
            
        default: break
        }
    }
}

struct MissingClientsRequestUserInfoKeys {
    static let clients = "clients"
}

public struct MissingClientsMap {

    /// The mapping from user-id's to an array of missing clients for that user `{ <user-id>: [<client-id>] }`
    let payload: [String: [String]]
    /// The `MissingClientsRequestUserInfoKeys.clients` key holds all missing clients
    let userInfo: [String: [String]]
    
    public init(_ missingClients: [UserClient], pageSize: Int) {
        
        let addClientIdToMap = { (clientsMap: [String : [String]], missingClient: UserClient) -> [String:[String]] in
            var clientsMap = clientsMap
            let missingUserId = missingClient.user!.remoteIdentifier!.transportString()
            clientsMap[missingUserId] = (clientsMap[missingUserId] ?? []) + [missingClient.remoteIdentifier]
            return clientsMap
        }
        
        var users = Set<ZMUser>()
        let missing = missingClients.filter {
            guard let user = $0.user else { return false }
            users.insert(user)
            return users.count <= pageSize
        }
        
        payload = missing.filter { $0.user?.remoteIdentifier != nil } .reduce([String:[String]](), combine: addClientIdToMap)
        userInfo = [MissingClientsRequestUserInfoKeys.clients: missing.map { $0.remoteIdentifier }]
    }
    
}


// { <user-id>: { <client-id>: { "id": int, "key": string } } }
typealias MissingClientsKeysPayload = [String: [String: [String: AnyObject]]]

// Used to fetch clients of particluar user when ui asks for them
extension UserClientRequestStrategy: ZMRemoteIdentifierObjectTranscoder {
    
    public func maximumRemoteIdentifiersPerRequestForObjectSync(sync: ZMRemoteIdentifierObjectSync!) -> UInt {
        return 1
    }
    
    public func requestForObjectSync(sync: ZMRemoteIdentifierObjectSync!, remoteIdentifiers identifiers: Set<NSUUID>!) -> ZMTransportRequest! {
        
        guard let userId = identifiers.first?.transportString() else { return nil }

        //GET /users/<user-id>/clients
        let path = NSString.pathWithComponents(["users", "\(userId)", "clients"])
        return ZMTransportRequest(path: path, method: .MethodGET, payload: nil)
    }
    
    public func didReceiveResponse(response: ZMTransportResponse!, remoteIdentifierObjectSync sync: ZMRemoteIdentifierObjectSync!, forRemoteIdentifiers remoteIdentifiers: Set<NSUUID>!) {
        
        guard let identifier = remoteIdentifiers.first,
              user = ZMUser(remoteID: identifier, createIfNeeded: true, inContext: managedObjectContext),
              selfClient = ZMUser.selfUserInContext(managedObjectContext).selfClient()
        else { return }
        
        // Create clients from the response
        guard let arrayPayload = response.payload.asArray() else { return }
        let clients: [UserClient] = arrayPayload.flatMap {
            guard let dict = $0 as? [String: AnyObject], identifier = dict["id"] as? String else { return nil }
            let client = UserClient.fetchUserClient(withRemoteId: identifier, forUser:user, createIfNeeded: true)
            client?.deviceClass = dict["class"] as? String
            return client
        }
        
        // Remove clients that have not been included in the response
        let deletedClients = Set(user.clients).subtract(Set(clients))
        deletedClients.forEach {
            $0.deleteClientAndEndSession()
        }
        
        // Add clients without a session to missed clients
        let newClients = clients.filter { !$0.hasSessionWithSelfClient }
        guard newClients.count > 0 else { return }
        selfClient.missesClients(Set(newClients))
        
        // add missing clients to ignored clients
        selfClient.addNewClientsToIgnored(Set(newClients))
    }
}

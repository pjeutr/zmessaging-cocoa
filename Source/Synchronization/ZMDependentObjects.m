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


#import "ZMDependentObjects.h"

#import "ZMManagedObject+Internal.h"



@interface ZMDependentObjects ()

@property (nonatomic) NSMapTable *dependenciesToDependants;

@end



@implementation ZMDependentObjects

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.dependenciesToDependants = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)addManagedObject:(ZMManagedObject *)dependantObject withDependency:(ZMManagedObject *)dependency;
{
    VerifyReturn(dependantObject != nil);
    VerifyReturn(dependency != nil);
    
    NSMutableOrderedSet *trackedDependants = [self.dependenciesToDependants objectForKey:dependency];
    
    if (trackedDependants == nil) {
        [self.dependenciesToDependants setObject:[NSMutableOrderedSet orderedSetWithObject:dependantObject] forKey:dependency];
    } else {
        [trackedDependants addObject:dependantObject];
    }
}

- (ZMManagedObject *)anyDependencyForObject:(ZMManagedObject *)dependant
{
    NSEnumerator *keyEnumbertor = [self.dependenciesToDependants keyEnumerator];
    ZMManagedObject *dependency;
    while ((dependency = keyEnumbertor.nextObject)) {
        NSOrderedSet *dependencies = [self.dependenciesToDependants objectForKey:dependency];
        if ([dependencies containsObject:dependant]) {
            return dependency;
        }
    }
    return nil;
}

- (void)enumerateManagedObjectsForDependency:(ZMManagedObject *)dependency withBlock:(BOOL(^)(ZMManagedObject *managedObject))block;
{
    VerifyReturn(dependency != nil);
    NSMutableOrderedSet *trackedDependants = [self.dependenciesToDependants objectForKey:dependency];
    if (trackedDependants == nil) {
        return;
    }
    NSMutableOrderedSet *remainingDependants = [NSMutableOrderedSet orderedSet];
    
    for (ZMManagedObject *mo in trackedDependants) {
        if (! block(mo)) {
            [remainingDependants addObject:mo];
        }
    }
    if (remainingDependants.count == 0) {
        [self.dependenciesToDependants removeObjectForKey:dependency];
    } else {
        [self.dependenciesToDependants setObject:remainingDependants forKey:dependency];
    }
}

@end
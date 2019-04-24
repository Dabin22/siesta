//
//  ObjcCompatibilitySpec.m
//  Siesta
//
//  Created by Paul on 2015/8/7.
//  Copyright © 2016 Bust Out Solutions. All rights reserved.
//

#import <Siesta/Siesta.h>
#import <Quick/Quick.h>
#import <Nimble/Nimble.h>
#import <Nocilla/Nocilla.h>
#import "SiestaTests-Swift.h"

@interface ObjcCompatibilitySpec : QuickSpec
@end

@interface ObjcObserver : NSObject<BOSResourceObserver>
@property (nonatomic,strong) NSMutableArray *eventsReceived;
@end

@implementation ObjcCompatibilitySpec

- (void) spec
    {
    // These specs are mostly just concerned with whether the code compiles.
    // They don't make many assertions about behavior, which is tested elsewhere.

    __block BOSService *service;
    __block BOSResource *resource;

    __block id _;  // Fake Swift’s `_ = foo()` idiom for @discardableResult functions

    beforeEach(^
        {
        service = [[TestService alloc] init];
        resource = [service resource:@"/foo"];
        });

    afterEach(^
        {
        service = nil;
        resource = nil;
        });

    beforeSuite(^{ [LSNocilla.sharedInstance start]; });
    afterSuite( ^{ [LSNocilla.sharedInstance stop]; });
    afterEach(  ^{ [LSNocilla.sharedInstance clearStubs]; });

    it(@"handles resource paths", ^
        {
        _ = [resource child:@"bar"];
        _ = [resource relative:@"../bar"];
        _ = [resource withParam:@"foo" value:@"bar"];
        _ = [resource withParams:@{@"foo": @"bar", @"baz": NSNull.null}];
        });

    it(@"handles requests", ^
        {
        stubRequest(@"GET", @"http://example.api/foo").andReturn(200);
        stubRequest(@"POST", @"http://example.api/foo").andReturn(200);

        expect([resource loadIfNeeded]).notTo(beNil());
        _ = [resource load];
        _ = [resource requestWithMethod:@"DELETE" data:[[NSData alloc] init] contentType:@"foo/bar" requestMutation:
            ^(NSMutableURLRequest *req)
                { req.HTTPMethod = @"POST"; }];
        _ = [resource requestWithMethod:@"POST" json:@{@"foo": @"bar"}];
        _ = [resource requestWithMethod:@"POST" json:@{@"foo": @"bar"} contentType:@"foo/bar" requestMutation:nil];
        _ = [resource requestWithMethod:@"POST" text:@"Ahoy"];
        _ = [resource requestWithMethod:@"POST" text:@"Ahoy" contentType:@"foo/bar" encoding:NSASCIIStringEncoding requestMutation:nil];
        _ = [resource requestWithMethod:@"POST" urlEncoded:@{@"foo": @"bar"} requestMutation:nil];
        _ = [resource loadUsingRequest:[resource requestWithMethod:@"POST" json:@{@"foo": @"bar"}]];

        XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"network calls finished"];
        BOSRequest *req = [[[[[[resource load]
            onCompletion:
                ^(BOSEntity *entity, BOSError *error)
                    { [expectation fulfill]; }]
            onSuccess: ^(BOSEntity *entity) { }]
            onNewData: ^(BOSEntity *entity) { }]  // TODO: This line leaks Resource instances, but the previous line doesn't. ‽‽‽
            onNotModified: ^{ }]
            onFailure: ^(BOSError *error) { }];
        [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];
        [req cancel];
        });

    describe(@"converting into Swift’s typesafe world", ^
        {
        void (^expectImmediateFailure)(BOSRequest*) = ^(BOSRequest *request)
            {
            XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"failed request"];
            __block BOOL immediatelyFailed = false;
            _ = [request onFailure: ^(BOSError *error)
                {
                [expectation fulfill];
                immediatelyFailed = true;
                }];
            [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];
            XCTAssert(immediatelyFailed);
            };

        it(@"handles invalid request method strings", ^
            {
            expectImmediateFailure(
                [resource requestWithMethod:@"FLARGBLOTZ"]);
            });

        it(@"handles invalid JSON objects", ^
            {
            expectImmediateFailure(
                [resource requestWithMethod:@"POST" json:[[NSData alloc] init]]);
            });
        });

    it(@"handles resource data", ^
        {
        stubRequest(@"GET", @"http://example.api/foo")
            .andReturn(200)
            .withHeader(@"Content-type", @"application/json")
            .withBody(@"{\"foo\": \"bar\"}");

        XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"network calls finished"];
        _ = [[resource load] onSuccess:^(BOSEntity *entity) { [expectation fulfill]; }];
        [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];

        expect(resource.jsonDict).to(equal(@{ @"foo": @"bar" }));
        expect(resource.jsonArray).to(equal(@[]));
        expect(resource.text).to(equal(@""));

        BOSEntity *entity = resource.latestData;
        expect(entity.content).to(equal(@{ @"foo": @"bar" }));
        expect(entity.contentType).to(equal(@"application/json"));
        expect([entity header:@"cOnTeNt-TyPe"]).to(equal(@"application/json"));

        entity.content = @"Wild and wooly content";
        [resource overrideLocalData:entity];
        entity = [[BOSEntity alloc] initWithContent:@"Homespun" contentType:@"knick/knack"];
        entity = [[BOSEntity alloc] initWithContent:@"Homespun" contentType:@"knick/knack" headers: @{}];
        [resource overrideLocalData:entity];

        expect(resource.latestError).to(beNil());
        });

    it(@"handles HTTP errors", ^
        {
        stubRequest(@"GET", @"http://example.api/foo").andReturn(507);

        XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"network calls finished"];
        _ = [[resource load] onFailure:^(BOSError *error) { [expectation fulfill]; }];
        [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];

        BOSError *error = resource.latestError;
        expect(error.userMessage).to(equal(@"Server error"));
        expect(@(error.httpStatusCode)).to(equal(@507));

        expect(resource.latestData).to(beNil());
        });

    it(@"handles other errors", ^
        {
        BOSRequest *req = [resource loadUsingRequest:
            [resource requestWithMethod:@"POST" json:@{@"Foo": [[NSData alloc] init]}]];

        XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"network calls finished"];
        _ = [req onFailure:^(BOSError *error) { [expectation fulfill]; }];
        [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];

        BOSError *error = resource.latestError;
        expect(error.userMessage).to(equal(@"Cannot send request"));
        expect(@(error.httpStatusCode)).to(equal(@-1));
        });

    it(@"doesn’t add observers twice", ^   // special case because glue object obscures identity
        {
        ObjcObserver *observer0 = [[ObjcObserver alloc] init],
                     *observer1 = [[ObjcObserver alloc] init];
        NSString *owner = [@"I am a big important owner string!" mutableCopy];  // copy b/c string literal never released!
        _ = [resource addObserver:observer0];
        _ = [resource addObserver:observer0];
        _ = [resource addObserver:observer1];
        _ = [resource addObserver:observer0 owner:owner];

        __block int blockObserverCalls = 0;
        _ = [resource addObserverWithOwner:owner callback:^(BOSResource *resource, NSString *event) {
            blockObserverCalls++;
        }];

        stubRequest(@"GET", @"http://example.api/foo")
            .andReturn(200)
            .withHeader(@"Content-type", @"application/json")
            .withBody(@"{\"foo\": \"bar\"}");

        XCTestExpectation *expectation = [[QuickSpec current] expectationWithDescription:@"network calls finished"];
        _ = [[resource load] onSuccess:^(BOSEntity *entity) { [expectation fulfill]; }];
        [[QuickSpec current] waitForExpectationsWithTimeout:1 handler:nil];

        expect(observer0.eventsReceived).to(equal(@[@"ObserverAdded", @"Requested", @"NewData(Network)"]));
        expect(observer1.eventsReceived).to(equal(@[@"ObserverAdded", @"Requested", @"NewData(Network)"]));
        expect(@(blockObserverCalls)).to(equal(@3));

        [resource removeObserversOwnedBy:observer1];
        [resource wipe];  // forces observer cleanup
        expect(observer0.eventsReceived).to(equal(@[@"ObserverAdded", @"Requested", @"NewData(Network)", @"NewData(Wipe)"]));
        expect(observer1.eventsReceived).to(equal(@[@"ObserverAdded", @"Requested", @"NewData(Network)", @"stoppedObserving"]));
        });

    it(@"honors observer ownership", ^
        {
        ObjcObserver __weak *observerWeak = nil;
        @autoreleasepool {
            // Keep events array even after observer deallocated
            NSMutableArray *eventsReceived = [NSMutableArray array];
            ObjcObserver *observer = [[ObjcObserver alloc] init];
            observer.eventsReceived = eventsReceived;

            // Let Siesta ownership control observer lifecycle
            NSObject *owner = [[NSObject alloc] init];
            _ = [resource addObserver:observer owner:owner];
            observerWeak = observer;
            observer = nil;

            // Owner still around: we get events, observer lives on
            [resource wipe];
            expect(observerWeak).notTo(beNil());
            expect(eventsReceived).to(equal(@[@"ObserverAdded", @"NewData(Wipe)"]));

            // Owner still around: no more events, observer gone
            owner = nil;
            [resource wipe];
            expect(eventsReceived).to(equal(@[@"ObserverAdded", @"NewData(Wipe)", @"stoppedObserving"]));
        }
        expect(observerWeak).to(beNil());
        });

    // TODO: more BOSResourceObserver
    }

@end


@implementation ObjcObserver : NSObject

- (void) resourceChanged: (BOSResource*) resource
                   event: (NSString *) event
    {
    if(!self.eventsReceived)
        self.eventsReceived = [NSMutableArray array];
    [self.eventsReceived addObject:event];
    }

- (void) stoppedObservingResource: (BOSResource * _Nonnull) resource
    {
    [self.eventsReceived addObject:@"stoppedObserving"];
    }

@end

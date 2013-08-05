//
//  OHResource.m
//  ObjectiveHAL
//
//  Created by Bennett Smith on 7/30/13.
//  Copyright (c) 2013 Mobile App Machine LLC. All rights reserved.
//

#import "OHResource.h"
#import "OHLink.h"
#import "CSURITemplate.h"

@interface OHResource ()
@property (nonatomic, strong) NSDictionary *links;
@property (nonatomic, strong) NSDictionary *curies;
@property (nonatomic, strong) NSDictionary *embedded;
@end

@implementation OHResource

- (id)initWithJSONData:(id)jsonData
{
    self = [super init];
    if (self) {
        if ([jsonData isKindOfClass:[NSDictionary class]]) {
            NSDictionary *data = (NSDictionary *)jsonData;
            NSDictionary *linksData = [data objectForKey:@"_links"];
            NSDictionary *embeddedData = [data objectForKey:@"_embedded"];
            
            _curies = [OHResource curiesFromJSONData:[linksData objectForKey:@"curies"]];
            _links = [OHResource linksFromJSONData:linksData withCuries:_curies];
            _embedded = [OHResource embeddedFromJSONData:embeddedData withCuries:_curies];
            
        } else {
            // ERROR: Expecting an NSDictionary.
            self = nil;
        }
    }
    return self;
}

+ (OHResource *)resourceWithJSONData:(id)jsonData
{
    OHResource *resource = [[OHResource alloc] initWithJSONData:jsonData];
    return resource;
}

- (BOOL)isEqual:(id)object
{
    // TODO: Decide if this is good enough for testing equality of resources.
    // It might make sense to actually test the values of the properties in
    // the resource, though that would be slower.  If we did test the values,
    // the _links and _embedded sections could possibly be skipped.
    if ([object isKindOfClass:[self class]]) {
        OHLink *selfLink = [self linkForRel:@"self"];
        OHLink *otherSelfLink = [(OHResource *)object linkForRel:@"self"];
        return [selfLink isEqual:otherSelfLink];
    } else {
        return NO;
    }
}

- (NSUInteger)hash
{
    OHLink *selfLink = [self linkForRel:@"self"];
    return [selfLink hash];
}

+ (NSDictionary *)embeddedFromJSONData:(id)jsonData withCuries:(NSDictionary *)curies
{
    NSMutableDictionary *embedded = [NSMutableDictionary dictionary];
    for (id embedKey in jsonData) {
        if ([embedKey isKindOfClass:[NSString class]]) {
            NSString *linkRelation = (NSString *)embedKey;
            NSString *expandedRelation = [OHResource expandRelationIfPossible:linkRelation withCuries:curies];
            id embeddedJson = [jsonData objectForKey:linkRelation];
            if ([embeddedJson isKindOfClass:[NSDictionary class]]) {
                [embedded setValue:embeddedJson forKey:expandedRelation];
            } else if ([embeddedJson isKindOfClass:[NSArray class]]) {
                NSMutableArray *embeddedArray = [NSMutableArray array];
                [embedded setValue:embeddedArray forKey:expandedRelation];
                for (id obj in embeddedJson) {
                    [embeddedArray addObject:obj];
                }
            } else {
                NSLog(@"WARNING: Type of link data not recognized");
            }
        } else {
            NSLog(@"WARNING: Link key not recognized");
        }
    }
    return embedded;
}

+ (NSDictionary *)curiesFromJSONData:(id)jsonData
{
    NSMutableDictionary *curies = [NSMutableDictionary dictionary];
    if ([jsonData isKindOfClass:[NSArray class]]) {
        for (id curieArrayElement in jsonData) {
            OHLink *curieLink = [[OHLink alloc] initWithJSONData:curieArrayElement rel:@"curies"];
            [curies setValue:curieLink forKey:[curieLink name]];
        }
    }
    return curies;
}

+ (NSDictionary *)linksFromJSONData:(id)jsonData withCuries:(NSDictionary *)curies
{
    NSMutableDictionary *links = [NSMutableDictionary dictionary];
    for (id linkKey in jsonData) {
        if ([linkKey isKindOfClass:[NSString class]]) {
            NSString *linkRelation = (NSString *)linkKey;
            if ([linkRelation isEqualToString:@"curies"] == NO) {
                NSString *expandedRelation = [OHResource expandRelationIfPossible:linkRelation withCuries:curies];
                id jsonLink = [jsonData objectForKey:linkRelation];
                if ([jsonLink isKindOfClass:[NSDictionary class]]) {
                    OHLink *link = [[OHLink alloc] initWithJSONData:jsonLink rel:expandedRelation];
                    [links setValue:link forKey:expandedRelation];
                } else if ([jsonLink isKindOfClass:[NSArray class]]) {
                    NSMutableArray *linkArray = [NSMutableArray array];
                    [links setValue:linkArray forKey:expandedRelation];
                    for (id linkArrayElement in jsonLink) {
                        OHLink *link = [[OHLink alloc] initWithJSONData:linkArrayElement rel:expandedRelation];
                        [linkArray addObject:link];
                    }
                } else {
                    NSLog(@"WARNING: Type of link data not recognized");
                }
            }
        } else {
            NSLog(@"WARNING: Link key not recognized");
        }
    }
    return links;
}

+ (NSString *)expandRelationIfPossible:(NSString *)rel withCuries:(NSDictionary *)curies
{
    NSURL *relURL = [NSURL URLWithString:rel];
    OHLink *curie = [curies objectForKey:[relURL scheme]];
    
    if (curie && [curie isTemplate]) {
        NSString *relValue = [relURL resourceSpecifier];
        CSURITemplate *template = [[CSURITemplate alloc] initWithURITemplate:[curie href]];
        rel = [template URIWithVariables:@{@"rel": relValue}];
    } else if (curie) {
        rel = [curie href];
    }
    
    return rel;
}

- (OHLink *)linkForRel:(NSString *)rel
{
    NSString *absoluteRel = [OHResource expandRelationIfPossible:rel withCuries:self.curies];
    id value = [self.links objectForKey:absoluteRel];
    if ([value isKindOfClass:[OHLink class]]) {
        return value;
    } else if ([value isKindOfClass:[NSArray class]]) {
        return [(NSArray *)value objectAtIndex:0];
    }
    return nil;
}

- (NSArray *)linksForRel:(NSString *)rel
{
    NSString *absoluteRel = [OHResource expandRelationIfPossible:rel withCuries:self.curies];
    id value = [self.links objectForKey:absoluteRel];
    if ([value isKindOfClass:[OHLink class]]) {
        return @[value];
    } else if ([value isKindOfClass:[NSArray class]]) {
        return (NSArray *)value;
    }
    return nil;
}

- (OHResource *)embeddedResourceForRel:(NSString *)rel
{
    OHResource *embeddedResource = [[self embeddedResourcesForRel:rel] objectAtIndex:0];
    return embeddedResource;
}

- (NSArray *)embeddedResourcesForRel:(NSString *)rel
{
    NSMutableArray *embeddedResources = [NSMutableArray array];
    
    NSString *absoluteRel = [OHResource expandRelationIfPossible:rel withCuries:self.curies];
    id value = [self.embedded objectForKey:absoluteRel];
    if ([value isKindOfClass:[NSArray class]]) {
        for (id embeddedJSONData in value) {
            OHResource *embeddedResource = [[OHResource alloc] initWithJSONData:embeddedJSONData];
            [embeddedResources addObject:embeddedResource];
        }
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        OHResource *embeddedResource = [[OHResource alloc] initWithJSONData:value];
        [embeddedResources addObject:embeddedResource];
    } else {
        // TODO: Handle error.
    }
    return embeddedResources;
}

- (NSString *)debugDescription
{
    NSString *dd = [NSString stringWithFormat:@"<%@: %p>{ links=%d, curies=%d, embedded=%d }",
                    NSStringFromClass([self class]), self, self.links.count, self.curies.count, self.embedded.count];
    return dd;
}
@end

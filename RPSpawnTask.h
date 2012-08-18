#import <Foundation/Foundation.h>

#ifndef RPSpawnTaskClass
#error RPSpawnTaskClass not defined! Must #define to a custom class name that won't conflict with other libraries using the same
#endif

@interface RPSpawnTaskClass : NSObject {
@private
	NSString *_processPath;
	NSArray *_arguments;
	pid_t _child;
	CFFileDescriptorRef _datafd;
	CFFileDescriptorRef _processfd;
	NSMutableData *data;
	void (^_completion)(int status, NSData *);
	int priorityAdjustment;
}

- (id)initWithProcessPath:(NSString *)processPath arguments:(NSArray *)arguments;
- (void)adjustPriority:(int)amount;
- (void)runToCompletion:(void (^)(int status, NSData *))completion;

@end

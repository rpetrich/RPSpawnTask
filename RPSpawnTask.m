#import "RPSpawnTask.h"

#import <sys/event.h>
#import <spawn.h>

@implementation RPSpawnTaskClass

- (id)initWithProcessPath:(NSString *)processPath arguments:(NSArray *)arguments
{
	if ((self = [super init])) {
		_processPath = [processPath copy];
		_arguments = [arguments copy];
	}
	return self;
}

- (void)dealloc
{
	[_processPath release];
	[_arguments release];
	[_completion release];
	[super dealloc];
}

- (void)finished
{
	int status = -1;
	int result;
	if (waitpid(_child, &result, 0) != -1)
		if (WIFEXITED(result))
			status = WEXITSTATUS(result);
	_completion(status, data);
	[data release];
	data = nil;
}

- (void)processNewData:(char *)buffer length:(size_t)length
{
	[data appendBytes:buffer length:length];
}

- (void)fileEnded
{
	CFFileDescriptorRef fd = _datafd;
	_datafd = NULL;
	if (_processfd == NULL)
		[self finished];
	CFFileDescriptorInvalidate(fd);
	CFRelease(fd);
}

- (void)adjustPriority:(int)amount
{
	priorityAdjustment += amount;
}

static void ProcessDataCallback(CFFileDescriptorRef f, CFOptionFlags callBackTypes, void *info)
{
	char buffer[4096];
	int fd = CFFileDescriptorGetNativeDescriptor(f);
	ssize_t bytes;
	do {
		bytes = read(fd, buffer, sizeof(buffer));
	} while ((bytes == -1) && (errno == EINTR));
	switch (bytes) {
		case -1:
		case 0:
			[(RPSpawnTaskClass *)info fileEnded];
			break;
		default:
			[(RPSpawnTaskClass *)info processNewData:buffer length:bytes];
			CFFileDescriptorEnableCallBacks(f, kCFFileDescriptorReadCallBack);
			break;
	}
}

- (void)processExited
{
	CFFileDescriptorRef fd = _processfd;
	_processfd = NULL;
	if (_datafd == NULL)
		[self finished];
	CFFileDescriptorInvalidate(fd);
	CFRelease(fd);
}

static void ProcessExitCallback(CFFileDescriptorRef f, CFOptionFlags callBackTypes, void *info)
{
    struct kevent kev;
    kevent(CFFileDescriptorGetNativeDescriptor(f), NULL, 0, &kev, 1, NULL);
    [(RPSpawnTaskClass *)info processExited];
}

- (void)runToCompletion:(void (^)(int status, NSData *))completion
{
	if (!completion)
		return;
	_completion = [completion copy];
	// Convert arguments to c-style
	size_t count = [_arguments count];
	const char *arguments[count + 2];
	arguments[0] = [_processPath UTF8String];
	for (size_t i = 0; i < count; i++)
		arguments[i+1] = [[_arguments objectAtIndex:i] UTF8String];
	arguments[count+1] = NULL;
	// Create pipe and setup mapping to stdout and stderr
	int fds[2];
	pipe(fds);
	posix_spawn_file_actions_t actions;
	posix_spawn_file_actions_init(&actions);
	posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
	posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
	posix_spawn_file_actions_addclose(&actions, fds[0]);
	// Spawn the new process
	posix_spawn(&_child, arguments[0], &actions, NULL, (void *)&arguments[0], NULL);
	posix_spawn_file_actions_destroy(&actions);
	// Adjust priority
	if (priorityAdjustment) {
		setpriority(PRIO_PROCESS, _child, priorityAdjustment);
	}
	// Close our instance of the writable end of the pipe
	close(fds[1]);
	// Create a kernel queue that receives exit events on the process
	struct kevent kev;
    EV_SET(&kev, _child, EVFILT_PROC, EV_ADD|EV_ENABLE, NOTE_EXIT, 0, NULL);
	int fd = kqueue();
    kevent(fd, &kev, 1, NULL, 0, NULL);
    // Schedule process exit callbacks
	CFFileDescriptorContext context = { 0, self, (void *)CFRetain, (void *)CFRelease, NULL };
	_processfd = CFFileDescriptorCreate(kCFAllocatorDefault, fd, true, ProcessExitCallback, &context);
	CFFileDescriptorEnableCallBacks(_processfd, kCFFileDescriptorReadCallBack);
	CFRunLoopSourceRef source = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, _processfd, 0);
	CFRunLoopRef runLoop = CFRunLoopGetMain();
	CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);
	CFRelease(source);
	// Schedule data callbacks on the read end of the pipe
	_datafd = CFFileDescriptorCreate(kCFAllocatorDefault, fds[0], true, ProcessDataCallback, &context);
	CFFileDescriptorEnableCallBacks(_datafd, kCFFileDescriptorReadCallBack);
	source = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, _datafd, 0);
	CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);
	CFRelease(source);
	data = [[NSMutableData alloc] init];
}

@end

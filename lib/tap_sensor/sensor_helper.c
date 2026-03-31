/*
 * sensor_helper.c — Lightweight C helper for reading Apple SPU accelerometer.
 *
 * Outputs lines of "x,y,z\n" to stdout at ~100Hz.
 * Designed to be spawned by the Ruby tap_sensor app and read via pipe.
 *
 * Build: cc -O2 -o lib/tap_sensor/sensor_helper lib/tap_sensor/sensor_helper.c \
 *        -framework CoreFoundation -framework IOKit
 *
 * Must run as root (sudo).
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <unistd.h>
#include <signal.h>

typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDServiceClientRef;
typedef void *IOHIDEventRef;

typedef IOHIDEventSystemClientRef (*CreateFunc)(CFAllocatorRef);
typedef void (*SetMatchingFunc)(IOHIDEventSystemClientRef, CFDictionaryRef);
typedef CFArrayRef (*CopyServicesFunc)(IOHIDEventSystemClientRef);
typedef int (*SetPropFunc)(IOHIDServiceClientRef, CFStringRef, CFTypeRef);
typedef void (*SetQueueFunc)(IOHIDEventSystemClientRef, dispatch_queue_t);
typedef void (*ActivateFunc)(IOHIDEventSystemClientRef);
typedef void (*RegEventCBFunc)(IOHIDEventSystemClientRef, void *, void *, void *);
typedef double (*GetFloatFunc)(IOHIDEventRef, int);

/* Event field encoding: (type << 16) | field_index */
/* Type 13 (orientation) with fields 1,2,3 = X,Y,Z */
#define FIELD_X ((13 << 16) | 1)
#define FIELD_Y ((13 << 16) | 2)
#define FIELD_Z ((13 << 16) | 3)

static GetFloatFunc g_getFloat = NULL;
static volatile sig_atomic_t g_running = 1;

static void handle_signal(int sig)
{
  (void)sig;
  g_running = 0;
}

static void event_callback(void *a, void *b, void *c, IOHIDEventRef event)
{
  (void)a;
  (void)b;
  (void)c;
  if (!event || !g_running)
    return;

  double x = g_getFloat(event, FIELD_X);
  double y = g_getFloat(event, FIELD_Y);
  double z = g_getFloat(event, FIELD_Z);

  /* Write CSV line to stdout — Ruby reads this via pipe */
  printf("%.6f,%.6f,%.6f\n", x, y, z);
  fflush(stdout);
}

int main(void)
{
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);
  signal(SIGPIPE, handle_signal);

  void *hid = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
  if (!hid)
  {
    fprintf(stderr, "sensor_helper: cannot load IOKit\n");
    return 1;
  }

  CreateFunc createClient = dlsym(hid, "IOHIDEventSystemClientCreate");
  SetMatchingFunc setMatching = dlsym(hid, "IOHIDEventSystemClientSetMatching");
  CopyServicesFunc copyServices = dlsym(hid, "IOHIDEventSystemClientCopyServices");
  SetPropFunc setProp = dlsym(hid, "IOHIDServiceClientSetProperty");
  SetQueueFunc setQueue = dlsym(hid, "IOHIDEventSystemClientSetDispatchQueue");
  ActivateFunc activate = dlsym(hid, "IOHIDEventSystemClientActivate");
  RegEventCBFunc regEventCB = dlsym(hid, "IOHIDEventSystemClientRegisterEventCallback");
  g_getFloat = dlsym(hid, "IOHIDEventGetFloatValue");

  if (!createClient || !g_getFloat || !regEventCB)
  {
    fprintf(stderr, "sensor_helper: missing IOKit symbols\n");
    return 1;
  }

  IOHIDEventSystemClientRef client = createClient(kCFAllocatorDefault);
  if (!client)
  {
    fprintf(stderr, "sensor_helper: cannot create event system client\n");
    return 1;
  }

  /* Match SPU accelerometer: PrimaryUsagePage=0xFF00, PrimaryUsage=3 */
  CFMutableDictionaryRef match = CFDictionaryCreateMutable(NULL, 0,
                                                           &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  int page = 0xFF00, usage = 3;
  CFNumberRef cfP = CFNumberCreate(NULL, kCFNumberIntType, &page);
  CFNumberRef cfU = CFNumberCreate(NULL, kCFNumberIntType, &usage);
  CFDictionarySetValue(match, CFSTR("PrimaryUsagePage"), cfP);
  CFDictionarySetValue(match, CFSTR("PrimaryUsage"), cfU);
  setMatching(client, match);
  CFRelease(cfP);
  CFRelease(cfU);
  CFRelease(match);

  /* Find matching service */
  CFArrayRef svcs = copyServices(client);
  if (!svcs || CFArrayGetCount(svcs) == 0)
  {
    fprintf(stderr, "sensor_helper: no accelerometer found\n");
    return 1;
  }

  /* Activate sensor by setting ReportInterval (10ms = 100Hz) */
  IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(svcs, 0);
  int interval = 10000;
  CFNumberRef val = CFNumberCreate(NULL, kCFNumberIntType, &interval);
  setProp(svc, CFSTR("ReportInterval"), val);
  CFRelease(val);

  /* Set up dispatch queue and start event delivery */
  dispatch_queue_t q = dispatch_queue_create("com.macmoan.sensor", DISPATCH_QUEUE_SERIAL);
  setQueue(client, q);
  regEventCB(client, (void *)event_callback, NULL, NULL);
  activate(client);

  /* Signal ready on stderr so the parent knows we're streaming */
  fprintf(stderr, "READY\n");
  fflush(stderr);

  /* Keep running until signaled */
  while (g_running)
  {
    usleep(100000); /* 100ms sleep — events arrive on the dispatch queue */
  }

  return 0;
}

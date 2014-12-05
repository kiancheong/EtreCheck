/***********************************************************************
 ** Etresoft
 ** John Daniel
 ** Copyright (c) 2014. All rights reserved.
 **********************************************************************/

#import "DiagnosticsCollector.h"
#import "NSMutableAttributedString+Etresoft.h"
#import "Utilities.h"
#import "TTTLocalizedPluralString.h"
#import "DiagnosticEvent.h"
#import "NSArray+Etresoft.h"
#import "Model.h"

// Collect diagnostics information.
@implementation DiagnosticsCollector

@synthesize dateFormatter = myDateFormatter;
@synthesize logDateFormatter = myLogDateFormatter;

// Constructor.
- (id) init
  {
  self = [super init];
  
  if(self)
    {
    self.name = @"diagnostics";
    self.title = NSLocalizedStringFromTable(self.name, @"Collectors", NULL);

    myDateFormatter = [[NSDateFormatter alloc] init];
   
    [myDateFormatter setDateFormat: @"yyyy-MM-dd-HHmmss"];
    [myDateFormatter setLocale: [NSLocale systemLocale]];

    myLogDateFormatter = [[NSDateFormatter alloc] init];
   
    [myLogDateFormatter setDateFormat: @"MMM d, yyyy, hh:mm:ss a"];
    [myLogDateFormatter setTimeZone: [NSTimeZone localTimeZone]];
    [myLogDateFormatter
      setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US"]];
    }
    
  return self;
  }

// Destructor.
- (void) dealloc
  {
  self.dateFormatter = nil;
  
  [super dealloc];
  }

// Perform the collection.
- (void) collect
  {
  [self
    updateStatus:
      NSLocalizedString(@"Checking diagnostics information", NULL)];

  [self collectDiagnostics];
  [self collectCrashReporter];
  [self collectDiagnosticReportCrashes];
  [self collectUserDiagnosticReportCrashes];
  [self collectDiagnosticReportHangs];
  [self collectUserDiagnosticReportHangs];
  [self collectPanics];
  [self collectCPU];
  
  if([[[Model model] diagnosticEvents] count] || insufficientPermissions)
    {
    [self.result appendAttributedString: [self buildTitle]];
      
    [self printDiagnostics];
    
    if(insufficientPermissions)
      {
      [self.result appendString: @"\n"];
      [self.result
        appendString:
          NSLocalizedString(
            @"/Library/Logs/DiagnosticReports permissions", NULL)];
      }
    
    [self.result appendCR];
    }
  
  [self
    setTabs: @[@28, @112, @196]
    forRange: NSMakeRange(0, [self.result length])];

  dispatch_semaphore_signal(self.complete);
  }

// Collect diagnostics.
- (void) collectDiagnostics
  {
  NSArray * args =
    @[
      @"-xml",
      @"SPDiagnosticsDataType"
    ];
  
  NSData * result =
    [Utilities execute: @"/usr/sbin/system_profiler" arguments: args];
  
  if(!result)
    return;
    
  NSArray * plist = [NSArray readPropertyListData: result];

  if(![plist count])
    return;
    
  NSArray * results =
    [[plist objectAtIndex: 0] objectForKey: @"_items"];
    
  if(![results count])
    return;

  for(NSDictionary * result in results)
    [self collectDiagnosticResult: result];
  }

// Collect a single diagnostic result.
- (void) collectDiagnosticResult: (NSDictionary *) result
  {
  NSString * name = [result objectForKey: @"_name"];
  
  if([name isEqualToString: @"spdiags_post_value"])
    {
    NSDate * lastRun =
      [result objectForKey: @"spdiags_last_run_key"];
    
    DiagnosticEvent * event = [DiagnosticEvent new];

    event.date = lastRun;
    
    NSString * details = [result objectForKey: @"spdiags_result_key"];
      
    if([details isEqualToString: @"spdiags_passed_value"])
      {
      event.type = kSelfTestPass;
      event.name = NSLocalizedString(@"Self test - passed", NULL);
      }
    else
      {
      event.type = kSelfTestFail;
      event.name = NSLocalizedString(@"Self test - failed", NULL);
      event.details = details;
      }
      
    [[[Model model] diagnosticEvents] setObject: event forKey: @"selftest"];
    }
  }

// Collect files in /Library/Logs/CrashReporter.
- (void) collectCrashReporter
  {
  NSArray * args =
    @[
      @"/Library/Logs/CrashReporter",
      @"-iname",
      @"*.crash"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  NSArray * files = [Utilities formatLines: data];
  
  NSString * permissionsError =
    @"find: /Library/Logs/DiagnosticReports: Permission denied";

  if([[files firstObject] isEqualToString: permissionsError])
    insufficientPermissions = YES;
  else
    [self parseDiagnosticReports: files];
  }

// Collect files in /Library/Logs/DiagnosticReports.
- (void) collectDiagnosticReportCrashes
  {
  NSArray * args =
    @[
      @"/Library/Logs/DiagnosticReports",
      @"-iname",
      @"*.crash"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  NSArray * files = [Utilities formatLines: data];
  
  NSString * permissionsError =
    @"find: /Library/Logs/DiagnosticReports: Permission denied";

  if([[files firstObject] isEqualToString: permissionsError])
    insufficientPermissions = YES;
  else
    [self parseDiagnosticReports: files];
  }

// Collect files in ~/Library/Logs/DiagnosticReports.
- (void) collectUserDiagnosticReportCrashes
  {
  NSString * diagnosticReportsDir =
    [NSHomeDirectory()
      stringByAppendingPathComponent: @"Library/Logs/DiagnosticReports"];

  NSArray * args =
    @[
      diagnosticReportsDir,
      @"-iname",
      @"*.crash"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  [self parseDiagnosticReports: [Utilities formatLines: data]];
  }

// Collect hang files in /Library/Logs/DiagnosticReports.
- (void) collectDiagnosticReportHangs
  {
  NSArray * args =
    @[
      @"/Library/Logs/DiagnosticReports",
      @"-iname",
      @"*.hang"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  NSArray * files = [Utilities formatLines: data];
  
  NSString * permissionsError =
    @"find: /Library/Logs/DiagnosticReports: Permission denied";

  if([[files firstObject] isEqualToString: permissionsError])
    insufficientPermissions = YES;
  else
    [self parseDiagnosticReports: files];
  }

// Collect hang files in ~/Library/Logs/DiagnosticReports.
- (void) collectUserDiagnosticReportHangs
  {
  NSString * diagnosticReportsDir =
    [NSHomeDirectory()
      stringByAppendingPathComponent: @"Library/Logs/DiagnosticReports"];

  NSArray * args =
    @[
      diagnosticReportsDir,
      @"-iname",
      @"*.hang"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  [self parseDiagnosticReports: [Utilities formatLines: data]];
  }

// Collect panic files in ~/Library/Logs/DiagnosticReports.
- (void) collectPanics
  {
  NSArray * args =
    @[
      @"/Library/Logs/DiagnosticReports",
      @"-iname",
      @"*.panic"
    ];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  NSArray * files = [Utilities formatLines: data];
  
  NSString * permissionsError =
    @"find: /Library/Logs/DiagnosticReports: Permission denied";

  if([[files firstObject] isEqualToString: permissionsError])
    insufficientPermissions = YES;
  else
    [self parseDiagnosticReports: files];
  }

// Collect CPU usage reports.
- (void) collectCPU
  {
  NSArray * args =
    @[
      @"/Library/Logs/DiagnosticReports",
      @"-iname",
      @"*.cpu_resource.diag"];
  
  NSData * data = [Utilities execute: @"/usr/bin/find" arguments: args];
  
  NSArray * files = [Utilities formatLines: data];
  
  NSString * permissionsError =
    @"find: /Library/Logs/DiagnosticReports: Permission denied";

  if([[files firstObject] isEqualToString: permissionsError])
    insufficientPermissions = YES;
  else
    [self parseDiagnosticReports: files];
  }

// Parse diagnostic reports.
- (void) parseDiagnosticReports: (NSArray *) files
  {
  for(NSString * file in files)
    [self createEventFromFile: file];
  }

// Create a new diagnostic event for a file.
- (void) createEventFromFile: (NSString *) file
  {
  NSString * typeString = [file pathExtension];
  
  EventType type = kUnknown;
  
  if([typeString isEqualToString: @"crash"])
    type = kCrash;
  else if([typeString isEqualToString: @"hang"])
    type = kHang;
  else if([typeString isEqualToString: @"panic"])
    type = kPanic;
  else if([typeString isEqualToString: @"diag"])
    type = kCPU;

  NSDate * date = [self parseFileDate: file];
  
  if((type != kUnknown) && date)
    {
    DiagnosticEvent * event = [DiagnosticEvent new];
    
    event.name = [Utilities sanitizeFilename: [file lastPathComponent]];
    event.date = date;
    event.type = type;
    event.file = file;
    
    // Include the entire log file for a panic.
    if(type == kPanic)
      event.details =
        [NSString
          stringWithContentsOfFile: file
          encoding: NSUTF8StringEncoding
          error: NULL];
    
    // Include just the first section for a CPU report.
    else if(type == kCPU)
      event.details = [self CPUReportHeader: file];
      
    // For everything else, just look for matching events in the log file.
    else
      event.details = [[Model model] logEntriesAround: date];
    
    [[[Model model] diagnosticEvents] setObject: event forKey: event.name];
    }
  }

// Parse a log file date.
- (NSDate *) parseFileDate: (NSString *) path
  {
  NSArray * parts =
    [[path lastPathComponent] componentsSeparatedByString: @"_"];
  
  if([parts count] > 1)
    return [self.dateFormatter dateFromString: [parts objectAtIndex: 1]];
    
  return nil;
  }

// Collect just the first section for a CPU report header.
- (NSString *) CPUReportHeader: (NSString *) file
  {
  NSString * contents =
    [NSString
      stringWithContentsOfFile: file
      encoding: NSUTF8StringEncoding
      error: NULL];
  
  NSArray * lines = [contents componentsSeparatedByString: @"\n"];

  __block NSMutableString * result = [NSMutableString string];
  
  __block NSUInteger lineCount = 0;
  
  [lines
    enumerateObjectsUsingBlock:
      ^(id obj, NSUInteger idx, BOOL * stop)
        {
        NSString * line = (NSString *)obj;
        
        [result appendString: line];
        [result appendString: @"\n"];
        
        if(lineCount++ > 20)
          *stop = YES;
        }];
    
  return result;
  }

// Print crash logs.
- (void) printDiagnostics
  {
  NSMutableDictionary * events = [[Model model] diagnosticEvents];
    
  NSArray * sortedKeys =
    [events
      keysSortedByValueUsingComparator:
        ^NSComparisonResult(id obj1, id obj2)
        {
        DiagnosticEvent * event1 = (DiagnosticEvent *)obj1;
        DiagnosticEvent * event2 = (DiagnosticEvent *)obj2;
        
        return [event2.date compare: event1.date];
        }];
    
  NSDate * then =
    [[NSDate date] dateByAddingTimeInterval: -60 * 60 * 24 * 3];
  
  for(NSString * name in sortedKeys)
    {
    DiagnosticEvent * event = [events objectForKey: name];
    
    switch(event.type)
      {
      case kPanic:
      case kSelfTestFail:
        [self printDiagnosticEvent: event name: name];
        break;
        
      default:
        if([then compare: event.date] == NSOrderedAscending)
          [self printDiagnosticEvent: event name: name];
      }
    }
  }

// Print a single diagnostic event.
- (void) printDiagnosticEvent: (DiagnosticEvent *) event
  name: (NSString *) name
  {
  if(event.type == kSelfTestFail)
    [self.result
      appendString:
        [NSString
          stringWithFormat:
            @"\t%@ \t- %@",
            [self.logDateFormatter stringFromDate: event.date],
            event.name]
      attributes:
        @{
          NSForegroundColorAttributeName : [[Utilities shared] red],
          NSFontAttributeName : [[Utilities shared] boldFont]
        }];
    
  else
    [self.result
      appendString:
        [NSString
          stringWithFormat:
            @"\t%@\t%@",
            [self.logDateFormatter stringFromDate: event.date],
            event.name]];
  
  if([event.details length])
    {
    NSAttributedString * detailsURL =
      [[Model model] getDetailsURLFor: name];

    if(detailsURL)
      {
      [self.result appendString: @" "];
      [self.result appendAttributedString: detailsURL];
      }
    }

  [self.result appendString: @"\n"];
  }

@end

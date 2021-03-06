/***********************************************************************
 ** Etresoft
 ** John Daniel
 ** Copyright (c) 2014. All rights reserved.
 **********************************************************************/

#import "ProcessesCollector.h"
#import "Model.h"
#import "Utilities.h"
#import "SubProcess.h"

// Collect information about processes.
@implementation ProcessesCollector

// Collect running processes.
- (NSMutableDictionary *) collectProcesses
  {
  NSArray * args = @[ @"-raxcww", @"-o", @"%mem, %cpu, comm" ];
  
  NSMutableDictionary * processes = [NSMutableDictionary dictionary];
    
  SubProcess * subProcess = [[SubProcess alloc] init];
  
  if([subProcess execute: @"/bin/ps" arguments: args])
    {
    NSArray * lines = [Utilities formatLines: subProcess.standardOutput];
    
    for(NSString * line in lines)
      {
      if([line hasPrefix: @"STAT"])
        continue;

      NSNumber * mem = nil;
      NSNumber * cpu = nil;
      NSString * command = nil;

      [self parsePs: line mem: & mem cpu: & cpu command: & command];

      if(!command)
        continue;
        
      if([command isEqualToString: @"EtreCheck"])
        continue;
        
      double RAM = [[Model model] physicalRAM];
      
      RAM = RAM * 1024 * 1024 * 1024;
      
      double usage = ([mem doubleValue] / 100.0) * RAM;
        
      [self
        recordProcess: command
        memory: usage
        cpu: [cpu doubleValue]
        in: processes];
      }
      
    // Don't forget the kernel.
    [self recordKernelTaskIn: processes];
    }
    
  [subProcess release];
  
  return processes;
  }

// Parse a line from the ps command.
- (void) parsePs: (NSString *) line
  mem: (NSNumber **) mem
  cpu: (NSNumber **) cpu
  command: (NSString **) command
  {
  NSScanner * scanner = [NSScanner scannerWithString: line];

  double memValue;
  
  bool found = [scanner scanDouble: & memValue];

  if(!found)
    return;

  *mem = [NSNumber numberWithDouble: memValue];
  
  double cpuValue;

  found = [scanner scanDouble: & cpuValue];

  if(!found)
    return;

  *cpu = [NSNumber numberWithDouble: cpuValue];

  [scanner scanUpToString: @"\n" intoString: command];
  }

// Record process information.
- (void) recordProcess: (NSString *) command
  memory: (double) usage
  cpu: (double) cpu
  in: (NSMutableDictionary *) processes
  {
  NSMutableDictionary * dict = [processes objectForKey: command];
  
  if(dict)
    {
    usage += [[dict objectForKey: @"mem"] doubleValue];
    cpu += [[dict objectForKey: @"cpu"] doubleValue];
    
    int count = [[dict objectForKey: @"count"] intValue] + 1;
    
    [dict setObject: [NSNumber numberWithDouble: usage] forKey: @"mem"];
    [dict setObject: [NSNumber numberWithDouble: cpu] forKey: @"cpu"];
    [dict setObject: [NSNumber numberWithInt: count] forKey: @"count"];
    }
  else
    {
    dict =
      [NSMutableDictionary
        dictionaryWithObjectsAndKeys:
          command, @"command",
          [NSNumber numberWithDouble: usage], @"mem",
          [NSNumber numberWithDouble: cpu], @"cpu",
          @1, @"count",
          nil];
       
    [processes setObject: dict forKey: command];
    }
  }

// Record process information.
- (void) recordKernelTaskIn: (NSMutableDictionary *) processes
  {
  NSArray * args = @[@"-l", @"2", @"-stats", @"pid,cpu,mem"];
  
  SubProcess * subProcess = [[SubProcess alloc] init];
  
  subProcess.usePseudoTerminal = YES;

  if([subProcess execute: @"/usr/bin/top" arguments: args])
    {
    NSArray * lines = [Utilities formatLines: subProcess.standardOutput];
    
    int count = 0;
    
    for(NSString * line in lines)
      {
      if(![line hasPrefix: @"0 "])
        continue;

      if(count++ == 0)
        continue;
        
      NSNumber * mem = nil;
      NSNumber * cpu = nil;

      [self parseTop: line mem: & mem cpu: & cpu];

      [self
        recordProcess: @"kernel_task"
        memory: [mem doubleValue]
        cpu: [cpu doubleValue]
        in: processes];
      }
    }
    
  [subProcess release];
  }

// Parse a line from the top command.
- (void) parseTop: (NSString *) line
  mem: (NSNumber **) mem
  cpu: (NSNumber **) cpu
  {
  NSScanner * scanner = [NSScanner scannerWithString: line];

  // I am only looking for pid 0, kernel_task and I should have already
  // checked the line for that prefix.
  int pid;
  
  bool found = [scanner scanInt: & pid];
  
  if(!found || (pid != 0))
    return;
    
  double cpuValue;

  found = [scanner scanDouble: & cpuValue];

  if(!found)
    return;

  *cpu = [NSNumber numberWithDouble: cpuValue];

  double memValue = [Utilities scanTopMemory: scanner];
    
  *mem = [NSNumber numberWithDouble: memValue];
  }

// Sort process names by some values measurement.
- (NSArray *) sortProcesses: (NSDictionary *) processes
  by: (NSString *) key
  {
  NSMutableArray * sorted = [[processes allValues] mutableCopy];
  
  [sorted
    sortUsingComparator:
      ^(id obj1, id obj2)
        {
        NSDictionary * process1 = (NSDictionary *)obj1;
        NSDictionary * process2 = (NSDictionary *)obj2;

        NSNumber * value1 = [process1 objectForKey: key];
        NSNumber * value2 = [process2 objectForKey: key];
        
        if(!value1 && value2)
          return (NSComparisonResult)NSOrderedDescending;
        
        if(value1 && !value2)
          return (NSComparisonResult)NSOrderedAscending;

        if([value1 doubleValue] < [value2 doubleValue])
          return (NSComparisonResult)NSOrderedDescending;
          
        if ([value1 doubleValue] > [value2 doubleValue])
          return (NSComparisonResult)NSOrderedAscending;

        return (NSComparisonResult)NSOrderedSame;
        }];
  
  return [sorted autorelease];
  }

@end

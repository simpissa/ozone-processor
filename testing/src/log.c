#include <stdarg.h>
#include <stdio.h>
#include "log.h"

log_priority_e log_priority;

void log_set_global_priority(log_priority_e priority) {
  log_priority = priority;
}

void plog(log_priority_e priority, const char *format, ...) {
    va_list args;
    va_start(args, format);
    if(priority >= log_priority) {
      vprintf(format, args);
    }
    va_end(args);
    return;
}

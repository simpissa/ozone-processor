#ifndef LOG_H
#define LOG_H

typedef enum {
  LOG_DEBUG,
  LOG_INFO,
  LOG_ERROR,
} log_priority_e;

extern log_priority_e log_priority;

void log_set_global_priority(log_priority_e priority);
void plog(log_priority_e priority, const char *format, ...);

#endif // LOG_H

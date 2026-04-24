#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include "ozone_config.h"
#include "log.h"
#include "json.h"

typedef enum {
  OZONE_CONFIG_RESET_VECTOR,
  OZONE_CONFIG_ENTRY,
  OZONE_CONFIG_TTBR0,
  OZONE_CONFIG_TERMINATE_VAL,
  OZONE_CONFIG_SP_EL0,
  OZONE_CONFIG_SP_EL1,
  OZONE_CONFIG_VBAR_EL1,
  OZONE_CONFIG_SPSR_EL1,
  OZONE_CONFIG_ELR_EL1,
  OZONE_CONFIG_NUM_STACK_PAGES,
  OZONE_CONFIG__MAX
} ozone_config_e;

const char* json_name_map[OZONE_CONFIG__MAX] = {
  "reset_vector",
  "entry",
  "ttbr0",
  "terminate_val",
  "sp_el0",
  "sp_el1",
  "vbar_el1",
  "spsr_el1",
  "elr_el1",
  "num_stack_pages",
};

static char* read_json_file(const char * const file_path) {
  int fd, err;
  fd = open(file_path, O_RDONLY);
  if (fd < 1) {
    plog(LOG_ERROR, "Couldn't open file: %s, error: %d\n", file_path, fd);
    exit(-1);
  }
  struct stat stats;
  if ((err = fstat(fd, &stats))) {
    plog(LOG_ERROR, "Couldn't fstat file: %s, error: %d\n", file_path, err);
    exit(-1);
  }
  const unsigned filesize_bytes = stats.st_size;
  char* json_text = malloc(filesize_bytes + 1);
  unsigned bytes_read = read(fd, json_text, filesize_bytes);

  if (bytes_read != filesize_bytes) {
    plog(LOG_ERROR, "Wanted to read %d bytes from %s, but only read %d bytes\n", filesize_bytes, file_path, bytes_read);
    exit(-1);
  }

  if ((err = close(fd))) {
    plog(LOG_ERROR, "Couldn't close file: %s\n", file_path);
    exit(-1);
  }
  json_text[filesize_bytes] = '\0';
  return json_text;
}

static ozone_config_e config_enum_from_string(const char * const entry_name) {
  for (int i = 0; i < OZONE_CONFIG__MAX; i++) {
    if (strcmp(entry_name, json_name_map[i]) == 0) {
      return i;
    }
  }
  return OZONE_CONFIG__MAX;
}

void ozone_config_read(ozone_config_t* config, const char * const config_path) {
  char* json_text = read_json_file(config_path);
  struct json_value_s* root = json_parse(json_text, strlen(json_text));
  struct json_object_s* object = json_value_as_object(root);
  plog(LOG_INFO, "JSON config: %s has %d elements in its root element\n", config_path, object->length);

  struct json_object_element_s* elem = object->start;
  while (elem != NULL) {
    struct json_string_s* elem_name = elem->name;
    ozone_config_e config_val = config_enum_from_string(elem_name->string);
    struct json_value_s* elem_value = elem->value;
    struct json_string_s* elem_string = json_value_as_string(elem_value);

    if (elem_string) {
        uint64_t val = strtoul(elem_string->string, NULL, 16);
        switch (config_val) {
        case OZONE_CONFIG_RESET_VECTOR: config->reset_vector = val; break;
        case OZONE_CONFIG_ENTRY:        config->entry = val; break;
        case OZONE_CONFIG_TTBR0:        config->ttbr0 = val; break;
        case OZONE_CONFIG_TERMINATE_VAL: config->terminate_val = val; break;
        case OZONE_CONFIG_SP_EL0:       config->sp_el0 = val; break;
        case OZONE_CONFIG_SP_EL1:       config->sp_el1 = val; break;
        case OZONE_CONFIG_VBAR_EL1:     config->vbar_el1 = val; break;
        case OZONE_CONFIG_SPSR_EL1:     config->spsr_el1 = val; break;
        case OZONE_CONFIG_ELR_EL1:      config->elr_el1 = val; break;
        case OZONE_CONFIG_NUM_STACK_PAGES: config->num_stack_pages = val; break;
        default: break;
        }
    }

    elem = elem->next;
  }
  free(json_text);
  return;
}

void ozone_config_print(ozone_config_t *config) {
  plog(LOG_INFO, "======== ozone_config_t ========\n");
  plog(LOG_INFO, "  reset_vector  : 0x%lx\n", config->reset_vector);
  plog(LOG_INFO, "  entry         : 0x%lx\n", config->entry);
  plog(LOG_INFO, "  ttbr0         : 0x%lx\n", config->ttbr0);
  plog(LOG_INFO, "  terminate_val : 0x%lx\n", config->terminate_val);
  plog(LOG_INFO, "  sp_el0        : 0x%lx\n", config->sp_el0);
  plog(LOG_INFO, "  sp_el1        : 0x%lx\n", config->sp_el1);
  plog(LOG_INFO, "  vbar_el1      : 0x%lx\n", config->vbar_el1);
  plog(LOG_INFO, "  spsr_el1      : 0x%lx\n", config->spsr_el1);
  plog(LOG_INFO, "  elr_el1       : 0x%lx\n", config->elr_el1);
  plog(LOG_INFO, "  num_stack_pages: 0x%lx\n", config->num_stack_pages);
  plog(LOG_INFO, "================================\n");
  return;
}

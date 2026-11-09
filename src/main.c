#include <time.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "truedrive.h"

#ifdef _WIN32
#include <direct.h>
#define makeDirectory(path) _mkdir(path)
#define removeDirectory(path) _rmdir(path)
#else
#include <unistd.h>
#define makeDirectory(path) mkdir(path, 0777)
#define removeDirectory(path) rmdir(path)
#endif

#define LOG_PREFIX "[True Drive] "
#define PROGRAM_NAME "truedrive"
#define WORK_FOLDER "true_drive"

// How many runs can share a timestamp before giving up on a unique folder name.
#define MAX_WORK_FOLDER_ATTEMPTS 1000

// Returns the start of the last path component.
static const char *baseName(const char *path)
{
  const char *base = path;

  for (const char *c = path; *c != '\0'; c++)
  {
#ifdef _WIN32
    if (*c == '/' || *c == '\\' || *c == ':')
#else
    if (*c == '/')
#endif
    {
      base = c + 1;
    }
  }

  return base;
}

static void printUsage(const char *program)
{
  fprintf(stderr, LOG_PREFIX "Usage: %s <encode|decode> -i <input file> -o <output path>\n", program);
  fprintf(stderr, LOG_PREFIX "  encode - Encodes a file to a binary noise video\n");
  fprintf(stderr, LOG_PREFIX "  decode - Decodes a binary noise video to a file\n");
}

// Creates "<output folder>/true_drive_<mode>_<timestamp>" and returns its path.
// Runs that start within the same second get a numeric suffix.
static char *createWorkDir(const char *outputPath, const char *mode)
{
  time_t currentTime = time(NULL);
  struct tm *timeInfo = localtime(&currentTime);
  if (timeInfo == NULL)
  {
    return NULL;
  }

  char name[64];
  snprintf(name, sizeof(name), "%s_%s_%04d%02d%02d_%02d%02d%02d",
           WORK_FOLDER, mode, timeInfo->tm_year + 1900, timeInfo->tm_mon + 1, timeInfo->tm_mday,
           timeInfo->tm_hour, timeInfo->tm_min, timeInfo->tm_sec);

  size_t folderLength = (size_t)(baseName(outputPath) - outputPath);
  size_t size = folderLength + strlen(name) + sizeof("_999");
  char *workDir = malloc(size);
  if (workDir == NULL)
  {
    return NULL;
  }

  memcpy(workDir, outputPath, folderLength);

  for (int attempt = 0; attempt < MAX_WORK_FOLDER_ATTEMPTS; attempt++)
  {
    if (attempt == 0)
    {
      snprintf(workDir + folderLength, size - folderLength, "%s", name);
    }
    else
    {
      snprintf(workDir + folderLength, size - folderLength, "%s_%d", name, attempt);
    }

    if (makeDirectory(workDir) == 0)
    {
      return workDir;
    }

    if (errno != EEXIST)
    {
      break;
    }
  }

  free(workDir);
  return NULL;
}

static char *withVideoExtension(const char *path)
{
  size_t size = strlen(path) + sizeof("." TD_VIDEO_EXTENSION);
  char *result = malloc(size);
  if (result != NULL)
  {
    snprintf(result, size, "%s." TD_VIDEO_EXTENSION, path);
  }

  return result;
}

int main(int argc, char *argv[])
{
  if (argc != 6)
  {
    printUsage(argc > 0 ? argv[0] : PROGRAM_NAME);
    return 1;
  }

  const char *mode = argv[1];
  const char *inputPath = NULL;
  const char *outputPath = NULL;

  for (int i = 2; i + 1 < argc; i += 2)
  {
    if (strcmp(argv[i], "-i") == 0)
    {
      inputPath = argv[i + 1];
    }
    else if (strcmp(argv[i], "-o") == 0)
    {
      outputPath = argv[i + 1];
    }
    else
    {
      fprintf(stderr, LOG_PREFIX "Invalid option '%s'\n", argv[i]);
      return 1;
    }
  }

  if (inputPath == NULL || outputPath == NULL)
  {
    fprintf(stderr, LOG_PREFIX "Input and output paths must be provided\n");
    return 1;
  }

  int encoding = strcmp(mode, "encode") == 0;
  if (!encoding && strcmp(mode, "decode") != 0)
  {
    fprintf(stderr, LOG_PREFIX "Invalid command '%s'\n", mode);
    return 1;
  }

  const char *outputName = baseName(outputPath);
  if (outputName[0] == '\0')
  {
    fprintf(stderr, LOG_PREFIX "Output path must end in a file name\n");
    return 1;
  }

  if (encoding && strchr(outputName, '.') != NULL)
  {
    fprintf(stderr, LOG_PREFIX "Output file should not have an extension\n");
    return 1;
  }

  char *workDir = createWorkDir(outputPath, mode);
  if (workDir == NULL)
  {
    fprintf(stderr, LOG_PREFIX "Failed to create work folder next to '%s'\n", outputPath);
    return 1;
  }

  printf(LOG_PREFIX "Input file '%s'\n", inputPath);
  printf(LOG_PREFIX "Work folder '%s'\n", workDir);
  fflush(stdout);

  TdStatus status;
  char *videoPath = NULL;

  if (encoding)
  {
    videoPath = withVideoExtension(outputPath);
    status = videoPath != NULL ? tdEncode(inputPath, videoPath, workDir) : TD_ERR_NO_MEMORY;
  }
  else
  {
    status = tdDecode(inputPath, outputPath, workDir);
  }

  if (status == TD_OK)
  {
    printf(LOG_PREFIX "Output written to '%s'\n", videoPath != NULL ? videoPath : outputPath);
  }
  else
  {
    fprintf(stderr, LOG_PREFIX "%s failed: %s\n", mode, tdStatusMessage(status));

    // Only succeeds if the run failed before writing any frames
    removeDirectory(workDir);
  }

  free(videoPath);
  free(workDir);

  return status == TD_OK ? 0 : 1;
}

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>

#define DEFAULT_NUM_LEN 512

char *itoa(long num, char *strnum, size_t size){
  int isNegative = 0;

  if(num == 0){
    strnum[0] = '0';
    strnum[1] = '\0';
    return strnum;
  }
  
  if(num < 0){
    isNegative = 1;
    num = -num;
  }
  
  int counter = 0;
  while(num > 0 && counter <(int)(size-1)){
      strnum[counter] = num % 10 + '0';
      num /= 10;
      counter ++;
  }
  
  if(isNegative){
    strnum[counter] = '-';
    counter++;
  } 
  
  strnum[counter] = '\0';
  
  for(int i=0; i<counter/2; i++){
    char temp = strnum[i];
    strnum[i] = strnum[counter-1-i];
    strnum[counter-1-i] = temp; 
  }

  return strnum;
}

int main()
{
    int fd = open("fork_bomb.log", O_CREAT | O_WRONLY | O_TRUNC, 0600);
    long count = 0;
    char intstr[DEFAULT_NUM_LEN];
    
    while(1){
        pid_t pid = fork();
        
        if(pid < 0){
            perror("fork");
            break;
        }
        
        if(pid == 0){
            // child: do nothing, just exist
            pause();
            return 0;
        }
        
        // parent: log count
        count++;
        lseek(fd, 0, SEEK_SET);
        memset(intstr, 0, sizeof(intstr));
        itoa(count, intstr, DEFAULT_NUM_LEN);
        write(fd, intstr, strlen(intstr));
    }
    
    close(fd);
    
    return 0;
}
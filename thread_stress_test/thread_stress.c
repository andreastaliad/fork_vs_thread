#include <stdlib.h>
#include <pthread.h>
#include <stdio.h>



#define THREAD_NUM 10000

void *task(void *args){
  return 0;
}

int main(){
  pthread_t pid[THREAD_NUM];
  
  int i = 0;
  for(i=0; i<THREAD_NUM; i++){
    if(pthread_create(&pid[i],NULL,task,NULL) > 0){
      for(int j=0; j<i; j++){
          pthread_join(pid[j],NULL);
          return 1;
      }
    }
  }

  return 0;
}

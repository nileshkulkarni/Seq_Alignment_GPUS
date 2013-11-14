
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <fstream>
#include <strstream>
#include <iostream>

using namespace std;
#define gap_penalty 3  //penalty to substitute with a gap //insertion or deletion
#define sub_penalty 5  //penalty to substitute with a different character

#define NO_BLOCKS  1024
#define NO_THREADS_PER_BLOCK 512 //kept as a multiple of 32 so as to make sure we make use of optimum number of warps

int findAlignment(int *outarr , char *outstr1 , char *outstr2, char *str1 , char *str2 , int l1 , int l2){
	int y = l1; //tracks the current index for string 1 i.e at any time l1 - y characters of str1 have been matched 
	int x = l2; //tracks the current index for string 2 i.e at any time l1 - x characters of str2 have been matched 
	//outarr is the matrix with alignment values inserted
	//outstr1 and outsrt2 are the final matched strings
	outstr1[l1+l2] = '\0'; 
	outstr2[l1+l2] = '\0';

	int val1,val2,val3;
	int t = l1+l2-1;
	while(y>0 && x>0){
		val1 = outarr[y*(l2+1) + x-1] +  gap_penalty;
        val2 = outarr[(y-1)*(l2+1) + x] + gap_penalty;
		val3 = outarr[(y-1)*(l2+1) + x-1] + ((str1[y-1] != str2[x-1]) * sub_penalty);	
		
		//
		if(outarr[y*(l2+1) + x] == val1){
			outstr2[t] = str2[x-1];
			outstr1[t--] = '_';  //blank
			x--;
			continue;
		}
		
		if(outarr[y*(l2+1) + x] == val2){
			outstr1[t] = str1[y-1];
			outstr2[t--] = '_';  //blank
			y--;
			continue;
		}

		if(outarr[y*(l2+1) + x] == val3){
			outstr2[t] = str2[x-1];
			outstr1[t--] = str1[y-1];  //substitute
			x--; y--;
			continue;
		}
	}

	//substitute the remaining elements with _ and other with elements as that of the input string
	for(int i=x;i>0 ; i--,t--){
		outstr2[t] = str2[i-1];
		outstr1[t] = '_';
	}

	for(int j=y;j>0 ; j--,t--){
		outstr1[t] = str1[j-1];
		outstr2[t] = '_';
	}

	//outstr1 = outstr1 + t;
	//outstr2 = outstr2 + t; 
	return t+1;
}





//device function for max of 3 numbers written avoiding many conditional statements.
__device__ int  mymax(int a ,int  b,int  c ){
	int max =a;
	max = (max<b)*b + (max>=b)*max;
	max = (max<c)*c + (max>=c)*max;
	return max;
}

//device function for min of 3 numbers written avoiding many conditional statements.
__device__ int  mymin3(int a ,int  b,int  c ){
	int min =a;
	min = (min>b)*b + (min<=b)*min;
	min = (min>c)*c + (min<=c)*min;
	return min;
}


//min of 2 nunmbers, host function
int  mymin(int a ,int  b){
	
	return (a>=b)*b + (a<b)*a;

}


//prints the input vector
void print_vector(int *arr ,  int len){

	for(int i=0; i<len;i++){
		printf("%d , ",arr[i]);
	}
	printf("\n");
}


__global__ void dpf(char *str1 , char *str2 , int *out_arr, int p, int q,int curr_x,int curr_y)
{
	int id = blockDim.x* blockIdx.x + threadIdx.x;
	

/*
	|
	|					diagonal_x   \				
	| diagonal_y           --------- |
	|								 /
   \_/ 

*/


	int diagonal_x ,diagonal_y;
		
	
//	while((curr_y != p) || (curr_x != q+1)){
		diagonal_x = curr_x+ id;
		diagonal_y = curr_y-id;

		if(diagonal_x <= q && diagonal_y>=0){

			out_arr[diagonal_y*(q+1) + diagonal_x] = (diagonal_x==0 && diagonal_y ==0)*0	 
												+(diagonal_x==0 && diagonal_y !=0)*(diagonal_y * gap_penalty)
												+(diagonal_x !=0 && diagonal_y == 0)*(diagonal_x * gap_penalty)
												+(diagonal_x !=0 && diagonal_y !=0)*mymin3(out_arr[diagonal_y*(q + 1) + diagonal_x -1] +  gap_penalty,
																						out_arr[(diagonal_y-1)*(q + 1)+ diagonal_x] + gap_penalty,
																						out_arr[(diagonal_y-1)*(q + 1)  + diagonal_x - 1] + 
																						        (str1[diagonal_y-1] != str2[diagonal_x-1]) * sub_penalty);	
			}

		//curr_x = curr_x + ((curr_y/p) * 1);
		//curr_y = mymin((curr_y +1),p);  		
		//__syncthreads();	
	//}
		

}
	

cudaError_t launchProg(char *str1 ,char *str2, int* outarr , int p, int q){
	// Steps in cuda program:
	// allocate variables space on the cudamemory
	// copy the data
	// call the kernel function

	char *str1_k;
	char *str2_k;
	int *out_k; //output 2d array
	printf("1\n");
	
	cudaError_t cudaStatus = cudaSetDevice(0);
    



	if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
        goto Error1;
    }

	// Allocate GPU buffers for three vectors (two input, one output)    .
	
printf("2\n");
	cudaStatus = cudaMalloc((void**)&out_k, (p+1)*(q+1) * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			fprintf(stdout, "cudaMalloc failed! , could not allot space to output array");
			//fprintf(stdout, "%s" , cudaGetErrorString(cudaStatus));
			goto Error1;
		}	



		cudaStatus = cudaMalloc((void**)&str1_k, p * sizeof(char));
		if (cudaStatus != cudaSuccess) {
			fprintf(stdout, "cudaMalloc failed!");
			goto Error1;
		}


			cudaStatus = cudaMalloc((void**)&str2_k, q *  sizeof(char));
		if (cudaStatus != cudaSuccess) {
			fprintf(stdout, "cudaMalloc failed!");
			goto Error1;
		}
	

		// Copy input vectors from host memory to GPU buffers.
		cudaStatus = cudaMemcpy(str1_k,str1, p * sizeof(char), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			fprintf(stdout, "cudaMemcpy failed!");
			goto Error1;
		}

		cudaStatus = cudaMemcpy(str2_k,str2, q * sizeof(char), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			fprintf(stdout, "cudaMemcpy failed!");
			goto Error1;
		}
	
		// Launch a kernel on the GPU with one thread for each element.
		/*
	|
	|				q	   \				
	| p           --------- |
	|					   /
   \_/ 

*/

		int curr_x =0, curr_y=0;
		while((curr_y != p) || (curr_x != q+1)){
			dpf<<<NO_BLOCKS, NO_THREADS_PER_BLOCK>>>(str1_k , str2_k ,out_k,p,q,curr_x,curr_y);
			curr_x = curr_x + ((curr_y/p) * 1);
			curr_y = mymin((curr_y +1),p);  			
		}

		
		
		cudaStatus = cudaGetLastError();
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
			goto Error1;
		}
    
		// cudaDeviceSynchronize waits for the kernel to finish, and returns
		// any errors encountered during the launch.
		cudaStatus = cudaDeviceSynchronize();
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
			goto Error1;
		}

		// Copy output vector from GPU buffer to host memory.
		cudaStatus = cudaMemcpy(outarr, out_k, (p + 1)*(q + 1)* sizeof(int), cudaMemcpyDeviceToHost);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMemcpy of output array failed!");
			goto Error1;
		}

Error1:
    cudaFree(out_k);
    return cudaStatus;
}

















int main() {
   // int n = 25;
//	char seq1[30000],seq2[30000];


	char *seq1 = "aishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfsjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfa";
	char *seq2=  "SailAwayFromTheShoresSailAwayFromTheShoresSailAwayFromTheShoressljflkajdlkjalkdsjflkjdfdsjkdfaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkhwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkhwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljflaishwariyaVipulajsljflkhwariyaVipulajsljflkajdlkjalkdsjflkjdfdaishwariyaVipulajsljflkajdlkjalkdsjflkjdfdsjkdfjjlsajfkvipualharssljfjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfasjflkjdfdsjkdfjjlsajfkvipualharssljfa";

	int size;
	ifstream file;
/*	
	file.open("data.txt",ios::in);

	if(file.is_open()){
		file.getline(seq1, 30000);
		file.getline(seq2,30000);
	//	printf("Input string 1 is %s\n %s ", seq1 , seq2);
		file.close();
	
	}
*/

//	else printf("file could not be opened");

	char *str1 = seq1;
    char *str2 = seq2;
	//char *str1 = "aishwariyaAbhiVipul";
	//char *str2 = "aishwariyaVipul";
	int l1 = strlen(str1);
	int l2 = strlen(str2);
	char *outstr1  = new char[l1+l2+1];
	char *outstr2  = new char[l2+l2+1];
	int *outarr = new int[(l1+1)*(l2+1)];
    // Add vectors in parallel.
    cudaError_t cudaStatus  = launchProg(str1 , str2 , outarr , l1 , l2);
	
		
	if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "launchProg failed!");
        return 1;
    }


	int offset = findAlignment(outarr , outstr1 , outstr2 , str1 , str2 ,l1,l2);
	printf("Aligned Strings are : \n %s \n %s \n" , outstr1 + offset, 
									outstr2+offset);


//output the table
/*   
	for(int i=0;i<=l1;i++){
	   for(int j=0;j<=l2;j++){
		   printf("%d " , outarr[i*(l2+1) + j]);
	   }
	   printf("\n");
   }
*/	


    // cudaDeviceReset must be called before exiting in order for profiling and
    // tracing tools such as Nsight and Visual Profiler to show complete traces.
    cudaStatus = cudaDeviceReset();
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaDeviceReset failed!");
        return 1;
    }
 return 0;
}



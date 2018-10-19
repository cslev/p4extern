# p4extern
This repository's aim is to (try to) show how extern functions should be implemented (some more high-level details of implementing a ROHC header compression module as a P4 extern can be found [here](https://arxiv.org/abs/1611.05943).

Basically, there are two ways to do this:
 a) adding your feature to the list of primitives (**primitives.cpp** under behavioral-model/targets/simple_switch/)
 
 b) or the more proper way of defining it as an extern 

First, we follow the second path and (might) cover the first one as well)

But, first things first, get the sources
```
$ git clone --recursive https://github.com/cslev/p4extern 
```
As one can see, it contains the two submodules (that need to be modified) we will need during implementing and supporting an extern: 
 - **BMv2** itself (we need to extend the switch architecture to support new externs - as one would need to implement an extern in a physical P4 switch as well)
 - **P4C compiler** to support calling your extern function


In order to ensure the submodules also checked out their further submodules, do the following steps for p4c
```
$ cd p4c
$ git submodule update --init --recursive
```


# Approach b)

## The function
We will create an extern function called *increase()* that should do nothing but increase a passed argument's value with one. I know it's not a big deal as we can already add two numbers together, but somewhere we should start to keep complexity low, right? 
Moreover, this *increase()* function in the beginning will not even do calculations, just prints out that it was called :)

## Step 1
Implement your own extern class in a well-defined (but barely documented way :)):
Create an **increase.cpp** file under the *behavioral-model/targets/* directory or, to easily follow the description below just  see mine in the repository and reproduce later if needed.

### Step 1.2
As it can be observed, it has some basic but necessary function calls (init() override and imports (*using bm::....*)) - for more details about this, again refer to the paper shared in the link above.
The important part here is that the function we would like to have at the end called in our P4 application is called *increased()* and implemend inside the class ExternIncrease. 

### Step 1.3
Once it is ready, we register our extern  with **BM_REGISTER_EXTERN_...** primitives

### Step 1.4 
We need to have a simple **int** function that will be called/used by the *simple_switch.cpp* itself. For now, it does nothing just returns 0.

## Step 2
Now, we extend our simple switch model to support/include our freshly made extern function

### Step 2.1
Edit */behavioral-model/targets/simple_switch/simple_switch.cpp* and add the following line after `extern int import_primitives();`:
```
extern int import_extern_increase();
```
### Step 2.2.
Above, we have just defined the our 'nothing-but-returns-0' function as an extern, but we also need to call it.
Look for the line where the `import_primitives()` function is called, then add the following line below:
```
import_extern_increase();
```

### Step 2.3
Make our extern class to be compiled and linked. Extend the Makefile.am file by adding `increase.cpp` to the variable `libsimpleswitch_la_SOURCES`, i.e., look for the `libsimpleswitch_la_SOURCES` and make it look like this:
```
libsimpleswitch_la_SOURCES = \
simple_switch.cpp \
simple_switch.h \
primitives.cpp \
increase.cpp
```
Makefile itself does not need be modified as it uses this .am file during compiling the main sources.
If you did everything well so far, it should compile without errors.







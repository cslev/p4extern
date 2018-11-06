# p4extern
This repository's aim is to (try to) show how extern functions should be implemented (some more high-level details of implementing a ROHC header compression module as a P4 extern can be found [here](https://arxiv.org/abs/1611.05943).
Note that the steps described here are working, however we did not have too much time to deeply go into the details and also reveal the 'why' besides the 'what' :)

Basically, there are two ways to do this:

 a) adding your feature to the basic primitives (**primitives.cpp** under behavioral-model/targets/simple_switch/)
 
 b) or the more proper way of defining it in an extern library

First, we follow path *a)* and (might) cover the *b)* as well)

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

Then, compile each of the from scratch with all their dependencies to assure yourself if a compilation error happens later on, it is because of your extern related modifications.
In order to do this, follow the instruction in their corresponding README.md file
 - [p4c](https://github.com/p4lang/p4c)
 - [behavioral-model](https://github.com/p4lang/behavioral-model)
 
# Note
Each of our modifications in the source code is surrounded by speciel characters:
```
-- LEVI (...)
-- END LEVI
```
 
# Approach a)
In this approach, we define our new extern function as a built-in primitive, i.e., we extend our BMv2 with a new function, but practically it won't be an extern, it will be an 'intern'.
The function itself will be a simple *logger* function that prints out the values of different variables to the standaard output in blue color. The name of the function is **p4_logger**
In order to have our function implemented, we need to modify a couple of files. First, let's modify the compiler (p4c) itself to enable it to compile a p4 application that would call our new function.
## P4C: p4include/v1model.h
Define the function as follows:
```
extern void p4_logger<T>(in T a);
```
## P4C: frontends/p4/fromv1.0/v1model.h
Add the new function to the constructor of V1Model:
```
class V1Model : public ::Model::Model {
 protected:
    V1Model() :
    ...
    p4_logger("p4_logger"),
    ...
```

Define it as well in the list of public fields:
```
public:
    ...
    ::Model::Elem       p4_logger;
    ...
```
## P4C: frontends/p4/fromv1.0/programStructure.cpp
We also need to populate its name in the ProgramStructure by adding **p4_logger** into the *used_names[]* array:
```
void ProgramStructure::populateOutputNames() {
    static const char* used_names[] = {
    ...
    "p4_logger",
    ...
```

## P4C: backends/bmv2/simple_switch/simpleSwitch.h:
Next, we need to add the definition of our function to the backend as well. One can see from this file how extern functions are defined according to their type, e.g., only a function, function and model, object and instance, etc.
Since in our case, we only create a simple function we will add the following line to the source:
```
EXTERN_CONVERTER_W_FUNCTION(p4_logger)
```
## P4C: backends/bmv2/simple_switch/simpleSwitch.cpp
Here, we need describe our function, in particular, how it will be represented in the final .json file. According to other functions here (e.g., random, mark_to_drop), it is easy to figure out how our new function should be described.
```
CONVERT_EXTERN_FUNCTION(p4_logger) {
  if (mc->arguments->size() != 1)
  {
    modelError("Expected 1 arguments for %1%", mc);
    return nullptr;
  }
  auto primitive = mkPrimitive("p4_logger");
  auto params = mkParameters(primitive);
  primitive->emplace_non_null("source_info", mc->sourceInfoJsonObj());
  auto dest = ctxt->conv->convert(mc->arguments->at(0)->expression);
  //std::cout << "p4_logger function is added to the switch application" << std::endl;
  params->append(dest);
  return primitive;
}
```
First, pay attention to the special way of how the function itself is defined. Then, in the `if` clause the number of arguments are being checked when this function is called. Accordingly, if you call your new extern with insuffient number of argumentsm the message in the `modelError` function will be printed out to you during compiling your p4 application.
Then, we register the primitives, add basic information to the json description, get the passed argument from the parameter list and append it to the parameters themselves.

Besides, we also need to add the following line above the defined functions (approx. around line 100) to make our function realizable:
```
EXTERN_CONVERTER_SINGLETON(p4_logger)
```

Now, the compiler is ready, it will know how our function looks like and what to generate and how when it is called in a p4 application.
Next, we add the main part of the function to the BMv2 itself.
## BMv2: targets/simple_switch/primitives.cpp
Here, we add our practical function definition as a `class`:
```
class p4_logger :
  public ActionPrimitive<const Data &> {
    void operator()(const Data &operand) {
      std::stringstream stream;
      stream << std::hex << operand.get_uint64();
      std::string result(stream.str());
      std::cout << "\033[1;34m[P4 logger]\t " << result << "\033[0m]" << std::endl;      
    }
  };
REGISTER_PRIMITIVE(p4_logger);
```
One might have noticed that the parameter's type is `Data`, which is derived from the inner structure of the BMv2, and it is described in *include/bm/bm_sim/data.h*. Getting into this source, we can see that there are some basic functions to convert Data to *int64*,*uint64*, etc. By default, it is converted to int, so if we want to print it out in `hex`, we use a simple stream conversion. (in order to minimize the modifications and the number of sources we touch, we rather add features to our `p4_logger` class rather than to make this hex string conversion in `data.h`.
At the end of the `class` definition, we also need to register our new primitive.

## Recompile everything
Now, both the compiler and the behavioral-model is ready to be recompiled. Note again that we assume that you have at least once compile both components as they are intended to be compiled.
Go to p4c/build and recompile the compiler:
```
p4c/build$ make -j4
```
Then, recompile behavioral-model:
```
behavioral-model/targets/simple_switch$ make -j4
```
Extend your application with the new function call to see how it works. Here, we add the following line to the *p4debug* application (note again that it is located in the repo) in the action `portfwd`:
```
p4_logger(hdr.ipv4.srcAddr);
p4_logger(hdr.ipv4.hdrChecksum);
p4_logger((bit<64>)0x3FF199999999999A);
```
What this application in essence will do is that any time a packet is received on any of its ports it will print out the values of `hdr.ipv4.srcAddr`, `hdr.ipv4.hdrChecksum` and a random hex number.

Compile your p4 application with the new compiler:
```
p4c/build$ ./p4c-bm2-ss ../../p4debug/monitoring.p4 -o ../../p4debug/monitoring.json
```
And finally, run it with the new BMv2:
```
p4extern$ sudo behavioral-model/targets/simple_switch/simple_switch -i 0@eth0 -i 1@eth1 --log-console p4debug/monitoring.json 
```
Note that the `p4debug` application here already contains the function call of `p4_logger`. 

After the application is running, send a packet to one of its port it will print out these variables in blue color:
```
[11:16:15.258] [bmv2] [T] [thread 27024] [0.0] [cxt 0] ../../p4debug/monitoring.p4(531) Primitive p4_logger(hdr.ipv4.srcAddr)
[P4 logger]	 a000001]
[11:16:15.258] [bmv2] [T] [thread 27024] [0.0] [cxt 0] ../../p4debug/monitoring.p4(532) Primitive p4_logger(hdr.ipv4.hdrChecksum)
[P4 logger]	 ce8]
[11:16:15.258] [bmv2] [T] [thread 27024] [0.0] [cxt 0] ../../p4debug/monitoring.p4(533) Primitive p4_logger((bit<64>)0x3FF199999999999A)
[P4 logger]	 3ff199999999999a]
```



# Approach b) *(incomplete - only hints and basics behind the idea is shown, but does not work (yet))*

## Modifications to the behavioral-model

## The function
We will create an extern function called *increase()* that should do nothing but increase a passed argument's value with one. I know it's not a big deal as we can already add two numbers together, but somewhere we should start to keep complexity low, right? 
Moreover, this *increase()* function in the beginning will not even do calculations, just prints out that it was called :)



### Step 1
Implement your own extern class in a well-defined (but barely documented way :)):
Create an **increase.cpp** file under the *behavioral-model/targets/* directory or, to easily follow the description below just  see mine in the repository and reproduce later if needed.

#### Step 1.2
As it can be observed, it has some basic but necessary function calls (init() override and imports (*using bm::....*)) - for more details about this, again refer to the paper shared in the link above.
The important part here is that the function we would like to have at the end called in our P4 application is called *increased()* and implemend inside the class ExternIncrease. 

#### Step 1.3
Once it is ready, we register our extern  with **BM_REGISTER_EXTERN_...** primitives

#### Step 1.4 
We need to have a simple **int** function that will be called/used by the *simple_switch.cpp* itself. For now, it does nothing just returns 0.

#### Step 2
Now, we extend our simple switch model to support/include our freshly made extern function

#### Step 2.1
Edit */behavioral-model/targets/simple_switch/simple_switch.cpp* and add the following line after `extern int import_primitives();`:
```
extern int import_extern_increase();
```
#### Step 2.2.
Above, we have just defined the our 'nothing-but-returns-0' function as an extern, but we also need to call it.
Look for the line where the `import_primitives()` function is called, then add the following line below:
```
import_extern_increase();
```

#### Step 2.3
Make our extern class to be compiled and linked. Extend the `Makefile.am` file by adding `increase.cpp` to the variable `libsimpleswitch_la_SOURCES`, i.e., look for the `libsimpleswitch_la_SOURCES` and make it look like this:
```
libsimpleswitch_la_SOURCES = \
simple_switch.cpp \
simple_switch.h \
primitives.cpp \
increase.cpp
```
Makefile itself does not need be modified as it uses this .am file during compiling the main sources.
If you did everything well so far, it should compile without errors.

## Modifications to the p4c compiler

### Step 1
Edit `p4c/p4include/v1model.p4`, and define our extern (we have defined it after `extern register<T>`:
```
extern ExternIncrease {
    ExternIncrease(bit<8> attribute_example);
    void increase();
}
```
### Step 2
Recompile p4c again
```
$ cd p4c/build/make
```
Now, p4c should know what this extern is once you define it in your P4 application.

## Use your own extern in your p4 application
We will use/extend our simple monitoring/debugging application found [here](https://github.com/cslev/p4debug) but also part of this repository.
### Step 1 
Define your extern

### Step 2
Instantiate and use your extern in `monitoring.p4`. Go to the MyIngress control processing and instantiate your extern in the beginning of the control processing:
```
@userextern @name("my_extern_increase")
    ExternIncrease(0x01) my_extern_increase;
```
Then, call also your function for testing. Now, each case a packet is received and going to be parsed would trigger the call of your function
```
my_extern_increase.increase();
```

### Step 3
Compile your P4 application with the modified compiler
```
$ cd path/to/the/clone/of/this/repository/p4extern
$ ./p4c/build/p4c-bm2-ss p4debug/monitoring.p4 -o p4debug/monitoring.json
```

### Step 4
Run your compiled P4 application with the modified simple switch 
```
$ cd path/to/the/clone/of/this/repository/p4extern
$ sudo ./behavioral-model-targets/simple_switch/simple_switch -i 0@eth1 --log-console p4debug/monitoring.json --log-console
```
Here, `eth1` is my physical interface, and it should be always brought up!
Note, furthermore that `--log-console` is useful to see a lot of stuffs a switch is doing

Use scapy or something else that can send a packets to this interface and wait for the results:)






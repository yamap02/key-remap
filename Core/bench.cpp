#include "Engine.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
int main(int argc,const char* argv[]){
    try {
        rekey::JSON config={{"schema_version",1},{"global",{{"thresholds_ms",{{"alone",200},{"held_down",500},{"simultaneous",50}}}}},{"profiles",rekey::JSON::array({{{"selected",true},{"name","Benchmark"},{"simple",rekey::JSON::array()},{"rules",rekey::JSON::array()}}})}};
        int count=10000;rekey::Identity identity;
        for(int i=1;i<argc;++i){std::string arg=argv[i];
            if(arg=="--config"&&i+1<argc){std::ifstream f(argv[++i]);config=rekey::JSON::parse(f);}
            else if(arg=="--events"&&i+1<argc)count=std::stoi(argv[++i]);
            else if(arg=="--vendor"&&i+1<argc)identity.vendor=std::stoi(argv[++i]);
            else if(arg=="--product"&&i+1<argc)identity.product=std::stoi(argv[++i]);
            else if(arg=="--physical"){std::cerr<<"Physical-to-virtual measurement requires an installed, authorized driver and physical input. This offline benchmark cannot report that latency.\n";return 69;}
            else {std::cerr<<"Usage: rekey-bench [--config FILE] [--events COUNT] [--vendor ID --product ID]\n";return 64;}
        }
        if(count<100||count>10000000)throw std::runtime_error("Event count must be 100...10000000");
        auto program=rekey::Program::compile(config,identity);auto rule_count=program.rules.size();rekey::Engine engine(std::move(program),identity);engine.update_context({});
        std::vector<double> timings;timings.reserve(count);size_t outputs=0;
        for(int i=0;i<count;++i){auto start=std::chrono::steady_clock::now();auto out=engine.process({4,(i%2)==0,uint64_t(i)});auto end=std::chrono::steady_clock::now();outputs+=out.size;timings.push_back(std::chrono::duration<double,std::micro>(end-start).count());}
        std::sort(timings.begin(),timings.end());rekey::JSON report={{"measurement","transform_only"},{"unit","microseconds"},{"events",count},{"output_events",outputs},{"rules",rule_count},{"p50",timings[size_t(count/2)]},{"p99",timings[size_t(count*0.99)]},{"physical_to_virtual_measured",false}};std::cout<<report.dump(2)<<'\n';return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 65;}
}

function test_FIR()
    close all;

    % ******************************************
    % configuration
    % ******************************************    
    param = struct();    
    param.INTERP = 3;
    param.DECIM = 1;
    param.NSTAGES = 20;
    param.WIDTH_IN = 18;
    param.ADDR_LINES = 9;
    param.BASEADDR_COEFF = 20;
    param.WIDTH_OUT = 43;
    
    param.CEIL_DECIM_SLASH_INTERP = ceil(param.DECIM/param.INTERP);
    param.FLOOR_DECIM_SLASH_INTERP = floor(param.DECIM/param.INTERP);
    param.DECIM_MOD_INTERP = mod(param.DECIM, param.INTERP);

    param.FIFOPTR_NBITS = nUnsignedBits(param.NSTAGES-1);
    param.NLOAD_NBITS = nUnsignedBits(ceil(param.INTERP / param.DECIM));
    param.COEFFPTR_NBITS = nUnsignedBits(param.INTERP * param.NSTAGES);
    param.MACCOUNT_NBITS = nUnsignedBits(floor(param.INTERP * param.NSTAGES / param.DECIM));
    param.BANKPTR_NBITS = nUnsignedBits(param.INTERP);
    param.PDELAY_SETMAC = 4;
    param.PDELAY_READMAC = 5; % one additional pipeline register for MAC output
    
    writeOut(param);

    param.minVal = -2 .^(param.WIDTH_IN-1);
    param.maxVal = 2 .^(param.WIDTH_IN-1)-1;

    % ******************************************
    % impulse response
    % ******************************************    
    if false
        ir = 1:(param.NSTAGES * param.INTERP);
    elseif false
        ir = 1:(param.NSTAGES * param.INTERP);
        ir = -ir;
    elseif true
        ir = rand(1, param.NSTAGES*param.INTERP);
        ir = floor(param.minVal+(param.maxVal-param.minVal)*ir);
    else
        ir = ones(1, param.NSTAGES*param.INTERP);    
    end
    writeIr(param, ir);
    
    % ******************************************
    % input data
    % ******************************************    
    inData = generateData(param, ir);
    % dummy samples to flush pipeline
    nDummy = 20;
    inData(end+nDummy) = 0;
    dlmwrite('generated/inData.txt', inData, 'precision', '%i');
    inData = inData(1:end-nDummy);
    
    % ******************************************
    % run Verilog simulator
    % ******************************************    
    
     importhdl('test_Fir.v')
  %   if true
        % use iverilog
   %      assert(!system('iverilog -Wall -g2005 -o tmp.vvp test_Fir.v'));
   %      assert(!system('vvp.exe tmp.vvp -lxt2'));    
   %  else
        % use modelsim
        % see // http://research.cs.berkeley.edu/class/cs/61c/modelsim/
        %assert(!system('vlib work')); % do once
  %       assert(!system('vlog test_FIR.v')); 
  %       assert(!system('vsim -c -do "run -all" top')); 
  %  end
    
    % ******************************************
    % load output
    % ******************************************    
    outData = load('generated/outData.txt');    
    refData = refModel(param, inData, ir);
    
    % reference model implicitly zero-pads input
    % output model may create less, equal or more samples, depending
    % how the pipeline exit of the last sample aligns
    % => always use shorter length
    nmin = min(numel(refData), numel(outData));
    refData = refData(1:nmin); 
    outData = outData(1:nmin);
    err = outData - refData;
    
    % ******************************************
    % compare
    % ******************************************    
    if max(abs(err)) < 0.01
        disp('implementation and reference give identical output');
    else
        figure(); hold on;
        plot(refData, 'k');
        plot(outData, 'b');
        plot(err, 'r');
        disp('*** results differ ***');
        assert(false);
    end
end

% ******************************************
% write configuration file "defines.v"
% ******************************************    
function writeOut(param, ir)
    f = fopen('generated/defines.v', 'w');
    assert(f);
    
    fn = fieldnames(param);
    for ix = 1:numel(fn)
        k = fn{ix};
        v = param.(k);
        if ~ischar(v)
            v=num2str(v);
        end
        fprintf(f, 'localparam %s = %s;\n', k, v);
    end
    fclose(f);
end

function d = generateData(param)
    if true
        s1 = linspace(param.minVal, param.maxVal, 1000);
        s2 = [ones(1, 30)*param.minVal, ones(1, 30)*param.maxVal, zeros(1, 30)];
        s3 = param.minVal + (param.maxVal-param.minVal)*rand(1, 200);
        d = [s1 s2 s3];
        d = floor(d);
    elseif true
        d = zeros(1, 4);
        d(1) = 1;
        d(902) = 256;
        d(1001) = 10;
        d = -100:1000;
    end
    d = d(:);
end

function d = refModel(param, inData, ir)
% upsample to intermediate rate
    d = [inData .'; zeros((param.INTERP-1), numel(inData))];
    d = d(:);
    
    % filter at intermediate rate
    d = conv(d(:), ir(:));
    
    % decimate to output rate
    d = d(1:param.DECIM:end);
    d = d(:);
end

function s = twosComplement(s, nBits)
    mask = s<0;
    s(mask) = 2^nBits+s(mask);
end

function n = nUnsignedBits(val)
    n = ceil(log2(val+1));
end

function writeIr(param, ir)
% blank RAM content
    ram = zeros(1, 2 .^ param.ADDR_LINES);

    % copy impulse response to its assigned address
    ram(1+param.BASEADDR_COEFF:1+param.BASEADDR_COEFF+numel(ir)-1) = ir;
    ram = twosComplement(ram, param.WIDTH_IN);

    % to file
    f = fopen('generated/ram_init.txt', 'w'); 
    assert(f);
    fprintf(f, '@0\n');
    fprintf(f, '%x\n', ram);
    fclose(f);

end

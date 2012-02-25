% author: Ben Zhang, nebgnahz@gmail.com
% based on Hijack.m, modified a lot to fit our algorithm
% since we are sending the data very fast, synchronization required

ManchesterData = wavread('android.wav');
% for nirjon android
% place for #define
SampleRate = 22050; % sample rate of audio, 16000/22000/44100
Theshold = 0.2;     % avoid misdetection and differentiate sample high/low
                    %           larger than  Threshold -> 1
                    %          smaller than -Threshold -> 0
                    % between -Threshold and Threshold -> lastSample
BitInterval = 11;   % manchester coding, double the interval tinyOS defines
                    % ussually this is obtained by counting, set it a little bit smaller
longInterval = 8;  % to predict the next phase change
shortInterval = 4;  % avoid misdetection of noise
                    % shortInterval should be short than half the BitInterval
ByteInterval = BitInterval * 12; 
                    % 11 bits inside a Byte, basically a little bit larger than 11*BitInterval
                    % use this to avoid error accumulation



% for dezhi iphone
% % place for #define
% SampleRate = 44100; % sample rate of audio, 16000/22000/44100
% Theshold = 0.2;     % avoid misdetection and differentiate sample high/low
%                     %           larger than  Threshold -> 1
%                     %          smaller than -Threshold -> 0
%                     % between -Threshold and Threshold -> lastSample
% BitInterval = 16;   % manchester coding, double the interval tinyOS defines
%                     % ussually this is obtained by counting, set it a little bit smaller
% longInterval = 14;  % to predict the next phase change
% shortInterval = 7;  % avoid misdetection of noise
%                     % shortInterval should be short than half the BitInterval
% ByteInterval = BitInterval * 12; 
%                     % 11 bits inside a Byte, basically a little bit larger than 11*BitInterval
%                     % use this to avoid error accumulation



% PKT_STATE, within a packet, has the meaning the word can tell
IDLE = 0;
DECODE_PKT = 1;
pktState = IDLE;

data = zeros(size(ManchesterData, 1)/BitInterval, 1); % Manchester decoded digital data
phase = 0;
lastPhase = 0;
lastSample = 0;
dataCount = 0;
bitFall = 0;        % after this is one, we know where to expect edge
dataValidFlag = 1;  % successfully detected a data 0/1
decodedData = zeros(12, 1); % 12 byte in a packet
tmp = 0;
% first step: convert raw manchester data to digital data
for i=1:length(ManchesterData)
    % first step, the detection of any useful header
    value = ManchesterData(i);          % get the raw value out for hard decode
    phase = phase + 1;                  % this phase is lasted one more, goes pretty the same as variable i

    % the hard decode process, refer to the description of THRESHOLD
    % note: Nirgon is using SUMSUNG android device, so toggle the sample result
    if (value > Theshold)
        sample = 0;
    elseif (value < -Theshold)
        sample = 1;
    else
        sample = lastSample;
    end
    
    % this step is Manchester decoding
    % to an array called data, UART bits are stored
    % parameters like data, dataValidFlag is used in the next step
    if (sample ~= lastSample)           % transition detected       
        lastSample = sample;
        diff = phase - lastPhase;       % diff is used for the duration measurement        
        if (bitFall == 0)               % we don't know the bit state currently
            if (diff > longInterval)    
            % only afterwards we can tell the data, because Manchester 0000..0 is the same as Manchester 1111..1            
                dataCount = dataCount + 1;
                data(dataCount) = sample;
                bitFall = 1;
            end
            lastPhase = phase;
            lastSample = sample;
        else
            if (diff > longInterval)    
            % only afterwards we can tell the data, because Manchester 0000..0 is the same as Manchester 1111..1            
                dataCount = dataCount + 1;
                data(dataCount) = sample;
                dataValidFlag = 1;
            else
                continue;
            end
            lastPhase = phase;            
        end
    end
    
    % only when data is valid, then process the packet decoding
    if (dataValidFlag == 1)        
        switch(pktState)
            case IDLE
                if (dataCount >= 24) % only then the packet is possible
                    % this step is used to catch the header to step into DECODE state
                    % TODO: this comparison may not be efficient
                    if (all(data(dataCount - 23:dataCount) == [1 0 1 1 1 1 1 1 1 1 0 1   1 0 1 1 1 1 1 1 1 1 0 1]'))
                        % data is 0xFFFF
                        highHeaderFlag = 1;
                        byteCountInPkt = 1;
                        pktState = DECODE_PKT;
                        DataPos = dataCount;
                        thisBytePos = i;
                        byteCountInPacket = 0;
%                         fprintf('%10d, %10d, %4d, foo\n', i, i-tmp, dataCount);
%                         tmp = i;
                    elseif (all(data(dataCount - 23:dataCount) == [1 0 0 1 1 1 1 1 1 1 1 1   1 0 0 1 1 1 1 1 1 1 1 1]'))
                        % data is 0xFEFE
                        lowHeaderFlag = 1;
                        byteCountInPkt = 1;
                        pktState = DECODE_PKT;
                        DataPos = dataCount;
                        thisBytePos = i;
%                         fprintf('%10d, %10d, %4d, bar\n', i, i-tmp, dataCount);
%                         tmp = i;
                    else
                        highHeaderFlag = 0;
                        lowHeaderFlag = 0;
                    end
                end
            case DECODE_PKT
                % here we should control the byte position
                if (i > thisBytePos + ByteInterval)
                    % well, this byte has ended after the time passed
                    % enough, change to next byte
                    byteCountInPkt = byteCountInPkt + 1;
                    thisBytePos = i;
                else
                    if (byteCountInPkt == 13)
                        pktState = IDLE;
%                         
%                         fprintf('%3d, %3d, %3d, %3d, %3d, %3d, %3d, %3d, %3d, %3d, %3d, %3d\n', ...
%                                 decodedData(1), decodedData(2), decodedData(3), decodedData(4), decodedData(5), decodedData(6),...
%                                 decodedData(7), decodedData(8), decodedData(9), decodedData(10), decodedData(11),decodedData(12));
                        
                        % TODO: handle the case where decodedData == -1
                        result = decodedData(1:2:end)*2^8 + decodedData(2:2:end);
                        for k=1:length(result)
                            if ( bitget(result(k), 16) == 1)
                                result(k) = mod(result(k), 32767)*(-1);
                            else
                                result(k) = mod(result(k), 32767);
                            end
                        end

                        result(1:3) = result(1:3) / 16384.0 * 9.8;
                        %-------------------------------------------
                        % here the full packet is obtained, print it
                        %-------------------------------------------
                        if (highHeaderFlag == 1)
                            fprintf('High: ');
                        else
                            fprintf('Low : ');
                        end
                        
                        fprintf('%7.3f, %7.3f, %7.3f, %7.3f, %7.3f, %7.3f\n', ...
                                result(1), result(2), result(3), result(4), result(5), result(6));
% 

                        highHeaderFlag = 0;
                        lowHeaderFlag = 0;
                    elseif (dataCount == DataPos + 12)
                        % expect data @ highHeaderDataPos + 12      
                        if (data(dataCount - 11) == 1 && data(dataCount - 10) == 0 && data(dataCount) == 1 ...
                                && data(dataCount-1) == bitand(sum( data(dataCount - 9:dataCount - 2) ),1))
                            decodedData(byteCountInPkt) = (2.^[0:7]) * data(dataCount - 9:dataCount - 2); 
                        else
                            decodedData(byteCountInPkt) = -1;
                        end
                        byteCountInPkt = byteCountInPkt + 1;
                        DataPos = dataCount;
                        thisBytePos = i;
                    end
                end
        end
        dataValidFlag = 0;
    end   
end
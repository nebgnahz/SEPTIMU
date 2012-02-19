% author: Ben Zhang, nebgnahz@gmail.com
% based on Hijack.m, modified a little bit to fit our algorithm

% read the recorded wave file here to load the data
% data = wavread('sample.wav');


% THRESHOLD is used to detect the digital signal, indicating the current sample whether a high or a low
THRESHOLD = 0;  
% LONG is used to detect start bit, basically LONG should be a little bit shorter than the clock
LONG = 16;      
% SHORT is used to avoid misdetection, any pulse/error within the SHORT duration will be ignored. Generally SHORT is shorter than half the clock
SHORT = 8;      


% UART STATE, within a byte
STARTBIT = 0;
SAMEBIT  = 1;
NEXTBIT  = 2;
STOPBIT  = 3;
STARTBIT_FALL = 4;
DECODE   = 5;


% PKT_STATE, within a packet
IDLE = 0;
FIRST_BYTE = 1;
SECOND_BYTE = 2;
END = 3;
START_FALL = 4;

% variables used to decode UART byte
sample=0;
lastSample=0;
phase2=0;
lastPhase2=0;
parityRx=0;
uartByte = 0;
dataWord = 0;

decState = STARTBIT;
bitNum = 0;
pktState= IDLE;
wordNum = 0;


% UART Decoding
for i=1:length(data)
    val = data(i);              % read current data
    phase2 = phase2 + 1;        % a new data means phase plus 1
    
    % digitally decode
    if (val < THRESHOLD)        
        sample = 1;
    else
        sample = 0;
    end
    
    if (sample ~= lastSample)   % transition
        diff = phase2 - lastPhase2;
        switch (decState)
            case STARTBIT
                if (lastSample == 0 && sample == 1)
                    % low->high transition. Now wait for a long period
                    decState = STARTBIT_FALL;
                end
            case STARTBIT_FALL
                if (( LONG < diff ))
                    % looks like we got a 1->0 transition, and long enough
                    bitNum = 0;
                    parityRx = 0;
                    uartByte = 0;
                    decState = DECODE;
                else
                    decState = STARTBIT;
                end
            case DECODE
                if (LONG < diff) 
                    % we got a valid sample.
                    if (bitNum < 8)
                        uartByte = bitshift(uartByte, -1) + bitshift(sample, 7);
                        bitNum = bitNum + 1;
                        parityRx =  bitget(parityRx + sample, 1);
                    elseif (bitNum == 8) 
                        % parity bit
                        if(sample ~= (parityRx & 1))
                            % a wrong byte
                            decState = STARTBIT;
                        else 
                            bitNum = bitNum + 1;
                        end
                    else
                        % we should now have the stopbit
                        if (sample == 1) 
                            % we have a new and valid byte!

                            wordNum = wordNum + 1;
                            fprintf('%d ', uartByte);   % here we are printing the raw decoded data
                            
                            %---------------------------------------------------------------
                            % process the packet here, sorry for the existing bug here
                            % gonna fix this soon, here we've got the uartByte
                            % the rest of the work is decode the packet
                            %---------------------------------------------------------------


                            % This is the end of processing the received byte!!!
                        else 
                            % not a valid byte.
                        end
                        decState = STARTBIT;
                    end            
                elseif (diff < SHORT) 
                    % don't update the phase as we have to look for the next transition
                    lastSample = sample;
                    continue;
                else 
                    % don't update the phase as we have to look for the next transition
                    lastSample = sample;
                    continue;
                end
        end
        lastPhase2 = phase2;
    end
    lastSample = sample;
end
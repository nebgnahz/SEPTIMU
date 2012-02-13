% author: Ben Zhang, nebgnahz@gmail.com
% based on Hijack.m, modified a little bit to fit our algorithm


% data = wavread('sample.wav');

THRESHOLD = 0;
LONG = 16;
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
    val = data(i);
    sample = data(i);
    phase2 = phase2 + 1;
    
    %{
    if (val < THRESHOLD)
        sample = 1;
    else
        sample = 0;
    end
    %}
    
    if (sample ~= lastSample)
        % transition
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
                            fprintf('%d ', uartByte);
                            switch (pktState)
                                case IDLE
                                    if (uartByte == hex2dec('FF'))
                                        pktState = START_FALL;
                                    end

                                case START_FALL
                                    if (uartByte == hex2dec('FF'))
                                        pktState = FIRST_BYTE;
                                        % this.AccData.Text = "Accelerometer:";
                                        % this.GyroData.Text = "Gyroscope:";
                                        % this.PktStateText.Text = "Status: start";
                                        wordNum = 0;
                                    else
                                        pktState = IDLE;
                                    end
                                case FIRST_BYTE
                                    dataWord = bitshift(uartByte, 8);
                                    pktState = SECOND_BYTE;                                    
                                case SECOND_BYTE
                                        dataWord = dataWord + uartByte;
                                        convertedData = dataWord / 16384.0 * 9.8;
                                        
                                        fprintf('%4.3f', convertedData);
                                        %{
                                        % selected print the results here
                                        if (2 <= wordNum && wordNum < 8)
                                        {
                                            this.AccData.Text = this.AccData.Text + String.Format("{0:00.000}", convertedData) + "  ";                                                    
                                        }
                                        else if (8 <= wordNum && wordNum < 14)
                                        {
                                            this.GyroData.Text = this.GyroData.Text + String.Format("{0:00.000}", convertedData) + "  ";
                                        }
                                        else if (wordNum == 14)
                                        {
                                            pktState = PKT_STATE.IDLE;
                                            wordNum = 0;
                                            break;
                                        }
                                        pktState = PKT_STATE.FIRST_BYTE;
                                        break;
                                        %}
                            end
                            
                            % This is where we receive the byte!!!
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
    
    

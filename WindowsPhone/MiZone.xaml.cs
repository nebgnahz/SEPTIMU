#undef SYNERGY
#define SEPTIMU

using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Phone.Controls;
using System.Windows.Input;
using Microsoft.Phone.Shell;                                                                                                                       
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Audio;



namespace MicrophoneTest
{
    public partial class MiZone : PhoneApplicationPage
    {
        private DispatcherTimer PlayDuration = new DispatcherTimer();

        private Microphone microphone = Microphone.Default;     // Object representing the physical microphone on the device
        private byte[] buffer;                                  // Dynamic buffer to retrieve audio data from the microphone
        private MemoryStream stream = new MemoryStream();       // Stores the audio data for later playback

        private MemoryStream powerSupplyStream = new MemoryStream();       // Stores the audio data for later playback

        private SoundEffectInstance soundInstance;              // Used to play back audio
        private bool powerIsOn = false;                         // Flag to monitor the state of power supply

        // Status images
        private BitmapImage blankImage;
        private BitmapImage microphoneImage;
        private BitmapImage speakerImage;


        /// <summary>
        /// Constructor 
        /// </summary>
        public MiZone()
        {
            InitializeComponent();
#if SYNERGY
            this.AccData.Visibility = Visibility.Collapsed;
            this.GyroData.Visibility = Visibility.Collapsed;
#endif
            this.PktStateText.Text = "";


            // Timer to simulate the XNA Framework game loop (Microphone is 
            // from the XNA Framework). We also use this timer to monitor the 
            // state of audio playback so we can update the UI appropriately.
            DispatcherTimer dt = new DispatcherTimer();
            dt.Interval = TimeSpan.FromMilliseconds(33);
            dt.Tick += new EventHandler(dt_Tick);
            dt.Start();


            PlayDuration.Interval = TimeSpan.FromMilliseconds(9000);
            PlayDuration.Tick += new EventHandler(PlayComplete);

            // Event handler for getting audio data when the buffer is full
            microphone.BufferReady += new EventHandler<EventArgs>(microphone_BufferReady);

            blankImage = new BitmapImage(new Uri("/icons/blank.png", UriKind.RelativeOrAbsolute));
            microphoneImage = new BitmapImage(new Uri("/icons/microphone.png", UriKind.RelativeOrAbsolute));
            speakerImage = new BitmapImage(new Uri("/icons/speaker.png", UriKind.RelativeOrAbsolute));
        }


        /// <summary>
        /// play continuously
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        void PlayComplete(object sender, EventArgs e)
        {
            PowerOnBySineWave();
        }



        /// <summary>
        /// Updates the XNA FrameworkDispatcher and checks to see if a sound is playing.
        /// If sound has stopped playing, it updates the UI.
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        void dt_Tick(object sender, EventArgs e)
        {
            try { FrameworkDispatcher.Update(); }
            catch { }
        }


        // Returns a sample value from the passed buffer,
        // taking into account the endian-ness of the system.
        private short ReadSample(byte[] buffer, int index)
        {
            // Ensure we're doing aligned reads.
            if (index % sizeof(short) != 0)
            {
                throw new ArgumentException("index");
            }

            if (index >= buffer.Length)
            {
                throw new ArgumentOutOfRangeException("index");
            }

            short sample = 0;
            if (!BitConverter.IsLittleEndian)
            {
                sample = (short)(buffer[index] << 8 | buffer[index + 1] & 0xff);
            }
            else
            {
                sample = (short)(buffer[index] & 0xff | buffer[index + 1] << 8);
            }
            return sample;
        }

        private int THRESHOLD = 0;
        private int LONG = 16;
        private int SHORT = 8;  
        private enum UART_STATE 
        {
            STARTBIT = 0,
	        SAMEBIT  = 1,
	        NEXTBIT  = 2,
	        STOPBIT  = 3,
	        STARTBIT_FALL = 4,
	        DECODE   = 5,
        };

        private enum PKT_STATE
        {
            IDLE = 0,
            FIRST_BYTE = 1,
            SECOND_BYTE = 2,
            END = 3,
            START_FALL = 4,
        }

        /// <summary>
        /// The Microphone.BufferReady event handler.
        /// Gets the audio data from the microphone and stores it in a buffer,
        /// then writes that buffer to a stream for later playback.
        /// Any action in this event handler should be quick!
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        void microphone_BufferReady(object sender, EventArgs e)
        {
            // Retrieve audio data
            microphone.GetData(buffer);
            short[] data = new short[buffer.Length / 2];

            // process data here
            // not implemented yet

            byte[] buffer_copy = buffer;


            int sample=0, lastSample=0;
            uint phase2=0, lastPhase2=0;
            byte parityRx=0;
            byte uartByte = 0;
            short dataWord = 0;
            UART_STATE decState = UART_STATE.STARTBIT;
            int bitNum = 0;
            PKT_STATE pktState= PKT_STATE.IDLE;
            int wordNum = 0;
            int count = 0;

            // UART Decoding
            
            for (int i = 0; i < buffer.Length - 1; i += 2)
            {
                data[i/2] = ReadSample(buffer, i);
                float val = data[i/2];
                phase2++;
                if (val < THRESHOLD)
                {
                    sample = 1;
                }
                else
                {
                    sample = 0;
                }

                // System.Diagnostics.Debug.WriteLine(sample + ",");

                if (sample != lastSample)
                {
                    // transition
                    
                    int diff = Convert.ToInt32(phase2 - lastPhase2);
                    switch (decState) 
                    {
                        case UART_STATE.STARTBIT:
                            if (lastSample == 0 && sample == 1)
                            {
                                // low->high transition. Now wait for a long period
                                decState = UART_STATE.STARTBIT_FALL;
                            }
                            break;
                        case UART_STATE.STARTBIT_FALL:
					        if (( LONG < diff ))
                            {
                                // looks like we got a 1->0 transition, and long enough
                                bitNum = 0;
                                parityRx = 0;
                                uartByte = 0;
                                decState = UART_STATE.DECODE;
                            } 
                            else
                            {
                                decState = UART_STATE.STARTBIT;
                            }
                            break;
				        case UART_STATE.DECODE:
					        if (LONG < diff) 
                            {
						        // we got a valid sample.
						        if (bitNum < 8) 
                                {
							        uartByte = (byte)((uartByte >> 1) + (sample << 7));
							        bitNum += 1;
                                    parityRx += (byte)sample;
                                } else if (bitNum == 8) 
                                {
                                    // parity bit
                                    if(sample != (parityRx & 0x01))
                                    {
                                        // a wrong byte
    								    decState = UART_STATE.STARTBIT;
	    						    }
                                    else 
                                    {
            						    bitNum += 1;
                                    }
							    }
                                else
                                {
							        // we should now have the stopbit
							        if (sample == 1) 
                                    {
								        // we have a new and valid byte!
                                        // System.Diagnostics.Debug.WriteLine("Got a byte here!" + uartByte);
                                        
                                        //////////////////////////////////////////////      
                                        
#if SYNERGY
                                        if (uartByte == 0xFF) 
                                        {
                                            count++;
                                            if (count % 2 == 0)
                                            {
                                                this.PktStateText.Text += "\n";
                                            }                                            
                                        }
                                        else
                                        {
                                            this.PktStateText.Text += uartByte.ToString() + " ";    
                                        }
                                        
#endif
#if SEPTIMU
                                        wordNum++;
                                        switch (pktState)
                                        {
                                            case PKT_STATE.IDLE:
                                                {
                                                    if (uartByte == 0xFF)
                                                    {
                                                        pktState = PKT_STATE.START_FALL;
                                                    }
                                                    break;
                                                }

                                            case PKT_STATE.START_FALL:
                                                {
                                                    if (uartByte == 0xFF)
                                                    {
                                                        pktState = PKT_STATE.FIRST_BYTE;
                                                        this.AccData.Text = "Accelerometer:";
                                                        this.GyroData.Text = "Gyroscope:";
                                                        this.PktStateText.Text = "Status: start";
                                                        wordNum = 0;

                                                        System.Diagnostics.Debug.WriteLine("");
                                                    }
                                                    else
                                                    {
                                                        pktState = PKT_STATE.IDLE;
                                                    }
                                                    break;
                                                }
                                            case PKT_STATE.FIRST_BYTE:
                                                {
                                                    dataWord = (short)((byte)uartByte << 8);
                                                    pktState = PKT_STATE.SECOND_BYTE;
                                                    break;
                                                }
                                            case PKT_STATE.SECOND_BYTE:
                                                {
                                                    dataWord += (short)uartByte;
                                                    double convertedData = dataWord / 16384.0 * 9.8;
                                                    // System.Diagnostics.Debug.WriteLine("{0:F5}", convertedData);
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
                                                }
                                            default:
                                                break;
                                        }
#endif
                                        // This is where we receive the byte!!!
								        //////////////////////////////////////////////
								    }
                                    else 
                                    {
								    // not a valid byte.
                                    }
                                    decState = UART_STATE.STARTBIT;
                                }
                            } 
                            else if (diff < SHORT) 
                            {
                                // don't update the phase as we have to look for the next transition
                                lastSample = sample;
                                continue;
                                
                            } 
                            else 
                            {
                                // don't update the phase as we have to look for the next transition
						        lastSample = sample;
						        continue;
					        }					
					        break;
                        default:
					        break;
                    }
                    lastPhase2 = phase2;
                }
		        lastSample = sample;
	        }

            // Store the audio data in a stream
            stream.Write(buffer, 0, buffer.Length);
        }

        /// <summary>
        /// for toggle switches
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void PowerOn(object sender, RoutedEventArgs e)
        {
            powerIsOn = true;
            this.UserHelp.Text = "powering";
            PowerOnBySineWave();
        }
        private void PowerOff(object sender, RoutedEventArgs e)
        {
            if (soundInstance.State == SoundState.Playing)
            {
                // In PLAY mode, user clicked the 
                // stop button to end playing back
                soundInstance.Stop();
                PlayDuration.Stop();
            }
            powerIsOn = false;
            this.UserHelp.Text = "power on first";
            StatusImage.Source = blankImage;
        }

        private void MISenseOn(object sender, RoutedEventArgs e)
        {
            // Get audio data in 1 second chunks
            microphone.BufferDuration = TimeSpan.FromMilliseconds(1000);

            // Allocate memory to hold the audio data
            buffer = new byte[microphone.GetSampleSizeInBytes(microphone.BufferDuration)];

            // Set the stream back to zero in case there is already something in it
            stream.SetLength(0);

            // Start recording
            microphone.Start();
            this.UserHelp.Text = "sensing";
            StatusImage.Source = microphoneImage;

            this.PktStateText.Text = "";
        }



        private void MISenseOff(object sender, RoutedEventArgs e)
        {
            if (microphone.State == MicrophoneState.Started)
            {
                // In RECORD mode, user clicked the 
                // stop button to end recording
                microphone.Stop();
            }
            if (true == powerIsOn)
            {
                UserHelp.Text = "powering";
                StatusImage.Source = speakerImage;
            }
            else
            {
                UserHelp.Text = "power on first";
                StatusImage.Source = blankImage;
            }
        }

        /// <summary>
        /// Plays the audio using SoundEffectInstance 
        /// so we can monitor the playback status.
        /// </summary>
        private void playSoundStereo()
        {
            // Play audio using SoundEffectInstance so we can monitor it's State 
            // and update the UI in the dt_Tick handler when it is done playing.
            SoundEffect sound = new SoundEffect(stream.ToArray(), 48000, AudioChannels.Stereo);
            soundInstance = sound.CreateInstance();
            soundInstance.Volume = 1.0f;
            soundInstance.Play();
        }


        /// <summary>
        /// start power supply
        /// </summary>
        private void PowerOnBySineWave()
        {
            byte[] buffer = new byte[SoundEffect.GetSampleSizeInBytes(TimeSpan.FromMilliseconds(10000),
                                                        48000, AudioChannels.Stereo)];
            
            for (int i = 2; i < buffer.Length  - 2; i = i + 4)
            {
                WriteSample(buffer, i, Convert.ToInt16( ( (1 << 15) - 1) * (Math.Sin(2 * Math.PI * 22000 * i / 4 / 48000))) );
            }

            stream.SetLength(0);
            // Store the audio data in a stream
            stream.Write(buffer, 0, buffer.Length);

            // Update the UI to reflect that
            // sound is playing
            StatusImage.Source = speakerImage;

            PlayDuration.Start();

            // Play the audio in a new thread so the UI can update.
            Thread soundThread = new Thread(new ThreadStart(playSoundStereo));
            soundThread.Start();
        }
        
        // Writes the sample value to the buffer,
        // taking into account the endian-ness of the system.
        private void WriteSample(byte[] buffer, int index, short sample)
        {
            // Ensure we're doing aligned writes.
            if (index % sizeof(short) != 0)
            {
                throw new ArgumentException("index");
            }

            if (index >= buffer.Length)
            {
                throw new ArgumentOutOfRangeException("index");
            }

            if (!BitConverter.IsLittleEndian)
            {
                buffer[index] = (byte)(sample >> 8);
                buffer[index + 1] = (byte)sample;
            }
            else
            {
                buffer[index] = (byte)sample;
                buffer[index + 1] = (byte)(sample >> 8);
            }
        }
    }
}
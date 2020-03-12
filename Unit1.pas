unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  Math, StdCtrls, Bass, ExtCtrls, Vcl.WinXCtrls;

type
  TForm1 = class(TForm)
    OpenDialog1: TOpenDialog;
    Timer1: TTimer;
    PB: TPaintBox;
    ToggleSwitch1: TToggleSwitch;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure PBPaint(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ToggleSwitch1Click(Sender: TObject);
  private
    bSkipSilence: Boolean;
    iStartAudio, iFinalAudio: qword;
    function PlayFile: Boolean;
    procedure ErrorPop(str: string);
    procedure SetLoopStart(position: qword);
    procedure SetLoopEnd(position: qword);
    procedure ScanPeaks2(decoder: HSTREAM);
    procedure DrawSpectrum;
    procedure DrawTime_Line(position: qword; Y: Integer; cl: TColor);
  public
  end;

type
  TScanThread = class(TThread)
  private
    Fdecoder: HSTREAM;
  protected
    procedure Execute; override;
  public
    constructor Create(decoder: HSTREAM);
  end;

procedure LoopSyncProc(handle: HSYNC; channel, data: DWORD;
  user: Pointer); stdcall;

var
  Form1: TForm1;
  lsync: HSYNC; // looping synchronizer handle
  chan: HSTREAM; // sample stream handle
  chan2: HSTREAM;
  loop: array [0 .. 1] of DWORD;
  killscan: Boolean;
  bpp: DWORD; // stream bytes per pixel
  wavebufL: array of smallint;
  wavebufR: array of smallint;
  mousedwn: Integer;
  Buffer: TBitmap;

implementation

{$R *.dfm}
// ------------------------------------------------------------------------------

procedure TForm1.FormCreate(Sender: TObject);
begin
  // check the correct BASS was loaded
  if (HIWORD(BASS_GetVersion) <> BASSVERSION) then
  begin
    MessageBox(0, 'An incorrect version of BASS.DLL was loaded', nil,
      MB_ICONERROR);
    Halt;
  end;

  // assigning layout properties
  ClientHeight := 201;
  ClientWidth := 600;
  Top := 100;
  Left := 100;
  Buffer := TBitmap.Create;
  Buffer.Width := PB.Width;
  Buffer.Height := PB.Height;
  PB.Parent.DoubleBuffered := true;

  // set array size
  setlength(wavebufL, ClientWidth);
  setlength(wavebufR, ClientWidth);

  // init vars
  loop[0] := 0;
  loop[1] := 0;

  // init BASS
  if not BASS_Init(-1, 44100, 0, Application.handle, nil) then
    ErrorPop('Can''t initialize device');

  // init timer for updating
  Timer1.Interval := 20; // ms
  Timer1.Enabled := true;

  ToggleSwitch1.State := tssOff;

  // main start play function
  if not PlayFile then
  begin
    BASS_Free();
    Application.Terminate;
  end;
end;

function TForm1.PlayFile: Boolean;
var
  filename: string;
  data: array [0 .. 2000] of smallint;
  i: Integer;
begin
  result := false;
  if OpenDialog1.Execute then
  begin
    filename := OpenDialog1.filename;
    BringWindowToTop(Form1.handle);
    SetForegroundWindow(Form1.handle);

    // creating stream
    chan := BASS_StreamCreateFile(false, pchar(filename), 0, 0, 0
{$IFDEF UNICODE} or BASS_UNICODE {$ENDIF});
    if chan = 0 then
    begin
      chan := BASS_MusicLoad(false, pchar(filename), 0, 0, BASS_MUSIC_RAMPS or
        BASS_MUSIC_POSRESET or BASS_MUSIC_PRESCAN
{$IFDEF UNICODE} or BASS_UNICODE {$ENDIF}, 1);
      if (chan = 0) then
      begin
        ErrorPop('Can''t play file');
        Exit;
      end;
    end;

    // playing stream and setting global vars
    for i := 0 to length(data) - 1 do
      data[0] := 0;
    bpp := BASS_ChannelGetLength(chan, BASS_POS_BYTE) div ClientWidth;
    // stream bytes per pixel
    if (bpp < BASS_ChannelSeconds2Bytes(chan, 0.02)) then
      // minimum 20ms per pixel (BASS_ChannelGetLevel scans 20ms)
      bpp := BASS_ChannelSeconds2Bytes(chan, 0.02);
    BASS_ChannelSetSync(chan, BASS_SYNC_END or BASS_SYNC_MIXTIME, 0,
      LoopSyncProc, nil); // set sync to loop at end
    BASS_ChannelPlay(chan, false); // start playing

    // getting peak levels in seperate thread, stream handle as parameter
    chan2 := BASS_StreamCreateFile(false, pchar(filename), 0, 0,
      BASS_STREAM_DECODE {$IFDEF UNICODE} or BASS_UNICODE {$ENDIF});
    if (chan2 = 0) then
      chan2 := BASS_MusicLoad(false, pchar(filename), 0, 0, BASS_MUSIC_DECODE
{$IFDEF UNICODE} or BASS_UNICODE {$ENDIF}, 1);
    TScanThread.Create(chan2); // start scanning peaks in a new thread
    result := true;
  end;
end;

procedure TForm1.DrawSpectrum;
var
  i, ht: Integer;
begin
  // clear background
  Buffer.Canvas.Brush.Color := clBlack;
  Buffer.Canvas.FillRect(Rect(0, 0, Buffer.Width, Buffer.Height));

  // draw peaks
  ht := ClientHeight div 2;
  for i := 0 to length(wavebufL) - 1 do
  begin
    Buffer.Canvas.MoveTo(i, ht);
    Buffer.Canvas.Pen.Color := clLime;
    Buffer.Canvas.LineTo(i, ht - trunc((wavebufL[i] / 32768) * ht));
    Buffer.Canvas.Pen.Color := clLime;
    Buffer.Canvas.MoveTo(i, ht + 2);
    Buffer.Canvas.LineTo(i, ht + 2 + trunc((wavebufR[i] / 32768) * ht));
  end;
end;

procedure TForm1.DrawTime_Line(position: qword; Y: Integer; cl: TColor);
var
  sectime: Integer;
  str: string;
  X: Integer;
begin
  sectime := trunc(BASS_ChannelBytes2Seconds(chan, position));
  X := position div bpp;

  // format time
  str := '';
  if (sectime mod 60 < 10) then
    str := '0';
  str := str + inttostr(sectime mod 60);
  str := inttostr(sectime div 60) + ':' + str;

  // drawline
  Buffer.Canvas.Pen.Color := cl;
  Buffer.Canvas.MoveTo(X, 0);
  Buffer.Canvas.LineTo(X, ClientHeight);

  // drawtext
  Buffer.Canvas.Font.Color := cl;
  Buffer.Canvas.Font.Style := [fsBold];
  if X > ClientWidth - 20 then
    dec(X, 40);
  SetBkMode(Buffer.Canvas.handle, TRANSPARENT);
  Buffer.Canvas.TextOut(X + 2, Y, str);
end;

procedure TForm1.ErrorPop(str: string);
begin
  // show last BASS errorcode when no argument is given, else show given text.
  if str = '' then
    Showmessage('Error code: ' + inttostr(BASS_ErrorGetCode()))
  else
    Showmessage(str);
  Application.Terminate;
end;

procedure TForm1.SetLoopStart(position: qword);
begin
  loop[0] := position;
end;

procedure TForm1.SetLoopEnd(position: qword);
begin
  loop[1] := position;
  BASS_ChannelRemoveSync(chan, lsync); // remove old sync
  lsync := BASS_ChannelSetSync(chan, BASS_SYNC_POS or BASS_SYNC_MIXTIME,
    loop[1], LoopSyncProc, nil); // set new sync

  if bSkipSilence then
    BASS_ChannelSetPosition(chan, loop[0], BASS_POS_BYTE);
end;

procedure LoopSyncProc(handle: HSYNC; channel, data: DWORD;
  user: Pointer); stdcall;
begin
  BASS_ChannelSetPosition(channel, loop[0], BASS_POS_BYTE);
end;

procedure TForm1.ScanPeaks2(decoder: HSTREAM);
var
  cpos, level: DWORD;
  peak: array [0 .. 1] of DWORD;
  position: DWORD;
  counter: Integer;
  bSetStart: Boolean;
begin
  cpos := 0;
  bSetStart := false;
  peak[0] := 0;
  peak[1] := 0;
  counter := 0;
  iStartAudio := 0;
  iFinalAudio := 0;

  while not killscan do
  begin
    level := BASS_ChannelGetLevel(decoder); // scan peaks
    if (peak[0] < LOWORD(level)) then
      peak[0] := LOWORD(level); // set left peak
    if (peak[1] < HIWORD(level)) then
      peak[1] := HIWORD(level); // set right peak

    if (peak[0] > 600) and (not bSetStart) then
    begin
      bSetStart := true;
      iStartAudio := BASS_ChannelGetPosition(decoder, BASS_POS_BYTE);
      if bSkipSilence then
        SetLoopStart(iStartAudio);
    end;

    if BASS_ChannelIsActive(decoder) <> BASS_ACTIVE_PLAYING then
    begin
      iFinalAudio := BASS_ChannelGetPosition(decoder, BASS_POS_BYTE);
      if bSkipSilence then
        SetLoopEnd(iFinalAudio);
      position := cardinal(-1); // reached the end
    end
    else
      position := BASS_ChannelGetPosition(decoder, BASS_POS_BYTE) div bpp;

    if position > cpos then
    begin
      inc(counter);
      if counter <= length(wavebufL) - 1 then
      begin
        wavebufL[counter] := peak[0];
        wavebufR[counter] := peak[1];
      end;

      if (position >= DWORD(ClientWidth)) then
        break;
      cpos := position;
    end;

    peak[0] := 0;
    peak[1] := 0;
  end;
  BASS_StreamFree(decoder); // free the decoder
end;

// ------------------------------------------------------------------------------

{ TScanThread }

constructor TScanThread.Create(decoder: HSTREAM);
begin
  inherited Create(false);
  Priority := tpNormal;
  FreeOnTerminate := true;
  Fdecoder := decoder;
end;

procedure TScanThread.Execute;
begin
  inherited;
  // desenho do audio
  Form1.ScanPeaks2(Fdecoder);
  Terminate;
end;

// ------------------------------------------------------------------------------

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  if bpp = 0 then
    Exit;
  DrawSpectrum; // draw peak waveform
  DrawTime_Line(loop[0], 12, TColor($FFFF00)); // loop start
  DrawTime_Line(loop[1], 24, TColor($00FFFF)); // loop end
  DrawTime_Line(BASS_ChannelGetPosition(chan, BASS_POS_BYTE), 0, TColor($FFFFFF)
    ); // current pos
  PB.Refresh;
end;

procedure TForm1.ToggleSwitch1Click(Sender: TObject);
begin
  bSkipSilence := ToggleSwitch1.State = tssOn;
  if bSkipSilence then
  begin
    SetLoopStart(iStartAudio);
    SetLoopEnd(iFinalAudio);
  end
  else
  begin
    SetLoopStart(0);
    SetLoopEnd(0);
  end;
end;

procedure TForm1.PBPaint(Sender: TObject);
begin
  if bpp = 0 then
    Exit;
  PB.Canvas.Draw(0, 0, Buffer);
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  Timer1.Enabled := false;
  bpp := 0;
  killscan := true;
  Buffer.Free;
  BASS_Free();
end;

end.

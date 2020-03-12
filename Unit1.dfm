object Form1: TForm1
  Left = 192
  Top = 103
  BorderStyle = bsDialog
  Caption = 'Silence Detection'
  ClientHeight = 200
  ClientWidth = 253
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object PB: TPaintBox
    Left = 0
    Top = 0
    Width = 253
    Height = 200
    Align = alClient
    OnPaint = PBPaint
  end
  object ToggleSwitch1: TToggleSwitch
    Left = 8
    Top = 168
    Width = 70
    Height = 20
    TabOrder = 0
    OnClick = ToggleSwitch1Click
  end
  object OpenDialog1: TOpenDialog
    Filter = 
      'Playable files|*.mp3;*.mp2;*.mp1;*.ogg;*.wav;*.aif;*.mo3;*.it;*.' +
      'xm;*.s3m;*.mtm;*.mod;*.umx|All files (*.*)|*.*'
    Title = 'Select a file to play'
    Left = 8
    Top = 8
  end
  object Timer1: TTimer
    Enabled = False
    OnTimer = Timer1Timer
    Left = 48
    Top = 8
  end
end

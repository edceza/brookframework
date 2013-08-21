(*
  Brook FCL HTTPApp Broker unit.

  Copyright (C) 2013 Yuriy Pilgun.

  http://brookframework.org

  All contributors:
  Plase see the file CONTRIBUTORS.txt, included in this
  distribution.

  See the file LICENSE.txt, included in this distribution,
  for details about the copyright.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*)

unit BrookHTTPDefsBroker;

{$mode objfpc}{$H+}

interface

uses
  BrookConsts, BrookHTTPConsts, BrookException, BrookUtils, HttpDefs, CustWeb,
  Classes, SysUtils, StrUtils;

function BrookFormatContentType: string;
function BrookHandleUnknownEncoding(ARequest:TRequest; const AContentType: string;
  AStream: TStream):boolean;
procedure BrookShowRequestException(AHandler: TWebHandler; R: TResponse; E: Exception);

implementation

uses
  FPJSON, JSONParser;

function BrookFormatContentType: string;
begin
  if BrookSettings.Charset <> ES then
    Result := BrookSettings.ContentType + BROOK_HTTP_HEADER_CHARSET +
      BrookSettings.Charset
  else
    Result := BrookSettings.ContentType;
end;


function BrookHandleUnknownEncoding(ARequest:TRequest; const AContentType: string;
  AStream: TStream):boolean;

  procedure ProcessJSONObject(AJSON: TJSONObject);
  var
    I: Integer;
  begin
    for I := 0 to Pred(AJSON.Count) do
      ARequest.ContentFields.Add(AJSON.Names[I] + EQ + AJSON.Items[I].AsString);
  end;

  procedure ProcessJSONArray(AJSON: TJSONArray);
  var
    I: Integer;
  begin
    for I := 0 to Pred(AJSON.Count) do
      if AJSON[I].JSONType = jtObject then
        ProcessJSONObject(AJSON.Objects[I])
      else
        raise Exception.CreateFmt('%s: Unsupported JSON format.', [ARequest.ClassName]);
  end;

var
  VJSON: TJSONData;
  VParser: TJSONParser;
begin
  Result := False;
  if Copy(AContentType, 1, Length(BROOK_HTTP_CONTENT_TYPE_APP_JSON)) =
    BROOK_HTTP_CONTENT_TYPE_APP_JSON then begin
    if BrookSettings.AcceptsJSONContent then
    begin
      AStream.Position := 0;
      VParser := TJSONParser.Create(AStream);
      try
        VJSON := VParser.Parse;
        case VJSON.JSONType of
          jtArray: ProcessJSONArray(TJSONArray(VJSON));
          jtObject: ProcessJSONObject(TJSONObject(VJSON));
        else
          raise Exception.CreateFmt('%s: Unsupported JSON format.', [ARequest.ClassName]);
        end;
      finally
        VJSON.Free;
        VParser.Free;
      end;
      Result := True;
    end;
  end;
end;


procedure BrookShowRequestException(AHandler: TWebHandler; R: TResponse; E: Exception);
var
  VHandled: Boolean = False;

  procedure HandleHTTP404;
  begin
    if not R.HeadersSent then begin
      R.Code := BROOK_HTTP_STATUS_CODE_NOT_FOUND;
      R.CodeText := BROOK_HTTP_REASON_PHRASE_NOT_FOUND;
      R.ContentType := BrookFormatContentType;
    end;

    if (BrookSettings.Page404File <> ES) and FileExists(BrookSettings.Page404File) then
      R.Contents.LoadFromFile(BrookSettings.Page404File)
    else
      R.Content := BrookSettings.Page404;

    R.Content := StringsReplace(R.Content, ['@root', '@path'],
      [BrookSettings.RootUrl, E.Message], [rfIgnoreCase, rfReplaceAll]);

    R.SendContent;
    VHandled := true;
  end;

  procedure HandleHTTP500;
  var
    ExceptionMessage,StackDumpString: TJSONStringType;
  begin
    if not R.HeadersSent then begin
      R.Code := BROOK_HTTP_STATUS_CODE_INTERNAL_SERVER_ERROR;
      R.CodeText := BROOK_HTTP_REASON_PHRASE_INTERNAL_SERVER_ERROR;
      R.ContentType := BrookFormatContentType;
    end;

    if (BrookSettings.Page500File <> ES) and FileExists(BrookSettings.Page500File) then begin
      R.Contents.LoadFromFile(BrookSettings.Page500File);
      R.Content := StringsReplace(R.Content, ['@error'],
        [E.Message], [rfIgnoreCase, rfReplaceAll]);
      if Pos('@trace',LowerCase(R.Content))>0 then
        R.Content := StringsReplace(R.Content, ['@trace'],
          [BrookDumpStack], [rfIgnoreCase, rfReplaceAll]); // DumpStack is slow and not thread safe
    end else begin
      R.Content := BrookSettings.Page500;
      StackDumpString := '';
      if BrookSettings.ContentType = BROOK_HTTP_CONTENT_TYPE_APP_JSON then begin
        ExceptionMessage := StringToJSONString(E.Message);
        if Pos('@trace',LowerCase(R.Content))>0 then
          StackDumpString  := StringToJSONString(BrookDumpStack(LF));
      end else begin
        ExceptionMessage := E.Message;
        if Pos('@trace',LowerCase(R.Content))>0 then
           StackDumpString  := BrookDumpStack;
      end;
      R.Content := StringsReplace(BrookSettings.Page500, ['@error', '@trace'],
        [ExceptionMessage, StackDumpString], [rfIgnoreCase, rfReplaceAll]);
    end;

    R.SendContent;
    VHandled := true;
  end;

begin
  if R.ContentSent then
    Exit;
  if Assigned(BrookSettings.OnError) then
  begin
    BrookSettings.OnError(R, E, VHandled);
    if VHandled then
      Exit;
  end;
  if Assigned(AHandler.OnShowRequestException) then
  begin
    AHandler.OnShowRequestException(R, E, VHandled);
    if VHandled then
      Exit;
  end;
  if AHandler.RedirectOnError and not R.HeadersSent then
  begin
    R.SendRedirect(Format(AHandler.RedirectOnErrorURL, [HTTPEncode(E.Message)]));
    R.SendContent;
    Exit;
  end;
  if E is EBrookHTTP404 then begin
    HandleHTTP404;
  end else begin
    HandleHTTP500;
  end
end;

end.

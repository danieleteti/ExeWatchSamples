// ***************************************************************************
//
// ExeWatch - DMVCFramework Integration Sample
//
// ServicesU: in-memory people service used by the controller.
// Demonstrates how ExeWatch timing wraps real business logic.
//
// ***************************************************************************

unit ServicesU;

interface

uses
  EntitiesU,
  MVCFramework.Container,
  System.Generics.Collections;

type
  IPeopleService = interface
    ['{8594D0FF-7E38-4416-AAA7-A516840FBABD}']
    function GetAll: TObjectList<TPerson>;
    function Search(const Query: String): TObjectList<TPerson>;
    procedure Add(const FirstName, LastName: String);
    procedure Delete(ID: Integer);
  end;

  TPeopleService = class(TInterfacedObject, IPeopleService)
  protected
    function GetAll: TObjectList<TPerson>;
    function Search(const Query: String): TObjectList<TPerson>;
    procedure Add(const FirstName, LastName: String);
    procedure Delete(ID: Integer);
  end;

procedure RegisterServices(Container: IMVCServiceContainer);

implementation

uses
  System.SysUtils,
  System.SyncObjs;

var
  GPeopleList: TObjectList<TPerson>;
  GNextID: Integer;
  GLock: TCriticalSection;

procedure RegisterServices(Container: IMVCServiceContainer);
begin
  Container.RegisterType(TPeopleService, IPeopleService,
    TRegistrationType.SingletonPerRequest);
end;

function TPeopleService.GetAll: TObjectList<TPerson>;
var
  I: Integer;
begin
  Result := TObjectList<TPerson>.Create(True);
  GLock.Enter;
  try
    for I := 0 to GPeopleList.Count - 1 do
      Result.Add(TPerson.Create(
        GPeopleList[I].ID.Value,
        GPeopleList[I].FirstName,
        GPeopleList[I].LastName,
        GPeopleList[I].DOB));
  finally
    GLock.Leave;
  end;
end;

function TPeopleService.Search(const Query: String): TObjectList<TPerson>;
var
  I: Integer;
  LQuery: string;
begin
  Result := TObjectList<TPerson>.Create(True);
  LQuery := LowerCase(Query);
  // Simulate a slow search if query is short (full table scan)
  if Length(Query) < 3 then
    Sleep(100 + Random(200));
  GLock.Enter;
  try
    for I := 0 to GPeopleList.Count - 1 do
      if LQuery.IsEmpty
         or (Pos(LQuery, LowerCase(GPeopleList[I].FirstName)) > 0)
         or (Pos(LQuery, LowerCase(GPeopleList[I].LastName)) > 0) then
        Result.Add(TPerson.Create(
          GPeopleList[I].ID.Value,
          GPeopleList[I].FirstName,
          GPeopleList[I].LastName,
          GPeopleList[I].DOB));
  finally
    GLock.Leave;
  end;
end;

procedure TPeopleService.Add(const FirstName, LastName: String);
var
  LID: Integer;
begin
  GLock.Enter;
  try
    LID := GNextID;
    Inc(GNextID);
    GPeopleList.Add(TPerson.Create(LID, FirstName, LastName, Date));
  finally
    GLock.Leave;
  end;
end;

procedure TPeopleService.Delete(ID: Integer);
var
  I: Integer;
begin
  GLock.Enter;
  try
    for I := GPeopleList.Count - 1 downto 0 do
      if GPeopleList[I].ID.Value = ID then
      begin
        GPeopleList.Delete(I);
        Break;
      end;
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GPeopleList := TObjectList<TPerson>.Create(True);
  GNextID := 1;

  // Seed with sample data
  GPeopleList.Add(TPerson.Create(GNextID, 'Henry', 'Ford', EncodeDate(1863, 7, 30))); Inc(GNextID);
  GPeopleList.Add(TPerson.Create(GNextID, 'Guglielmo', 'Marconi', EncodeDate(1874, 4, 25))); Inc(GNextID);
  GPeopleList.Add(TPerson.Create(GNextID, 'Antonio', 'Meucci', EncodeDate(1808, 4, 13))); Inc(GNextID);
  GPeopleList.Add(TPerson.Create(GNextID, 'Michael', 'Faraday', EncodeDate(1791, 9, 22))); Inc(GNextID);

finalization
  GPeopleList.Free;
  GLock.Free;

end.

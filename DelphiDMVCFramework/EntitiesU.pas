// ***************************************************************************
//
// ExeWatch - DMVCFramework Integration Sample
//
// EntitiesU: simple data entity used by the People CRUD demo.
//
// ***************************************************************************

unit EntitiesU;

interface

uses
  MVCFramework.Nullables, MVCFramework.Serializer.Commons;

type
  TPerson = class
  private
    fID: NullableInt32;
    fFirstName: String;
    fLastName: String;
    fDOB: TDate;
    function GetDOBStr: String;
  public
    property ID: NullableInt32 read fID write fID;
    property FirstName: String read fFirstName write fFirstName;
    property LastName: String read fLastName write fLastName;
    property DOB: TDate read fDOB write fDOB;
    /// <summary>Date of birth formatted for display in templates</summary>
    property DOBStr: String read GetDOBStr;
    constructor Create(AID: Integer; const AFirstName, ALastName: String; ADOB: TDate);
  end;

implementation

uses
  System.SysUtils;

constructor TPerson.Create(AID: Integer; const AFirstName, ALastName: String; ADOB: TDate);
begin
  inherited Create;
  fID := AID;
  fFirstName := AFirstName;
  fLastName := ALastName;
  fDOB := ADOB;
end;

function TPerson.GetDOBStr: String;
begin
  Result := FormatDateTime('yyyy-mm-dd', fDOB);
end;

end.

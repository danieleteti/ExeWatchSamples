// ***************************************************************************
//
// Delphi MVC Framework
//
// Copyright (c) 2010-2026 Daniele Teti and the DMVCFramework Team
//
// https://github.com/danieleteti/delphimvcframework
//
// ***************************************************************************
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
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
  public
    property ID: NullableInt32 read fID write fID;
    property FirstName: String read fFirstName write fFirstName;
    property LastName: String read fLastName write fLastName;
    property DOB: TDate read fDOB write fDOB;
    constructor Create(ID: Integer; FirstName, LastName: String; DOB: TDate);
  end;

implementation

constructor TPerson.Create(ID: Integer; FirstName, LastName: String; DOB: TDate);
begin
  inherited Create;
  fID := ID;
  fFirstName := FirstName;
  fLastName := LastName;
  fDOB := DOB;
end;


end.

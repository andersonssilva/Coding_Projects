Attribute VB_Name = "Module1"
'Need to associate each function to a button in Excel
Sub FetchNames()

Dim myPath As String
Dim myFile As String

myPath = Application.ActiveWorkbook.Path & "\Files to change name\"
'myPath = "C:\Users\asilva4\Documents\Copy from asilva server drive\Requests-Reports\Renaming Babel Raps Return\Files to change name\"
' Application.ActiveWorkbook.Path picks the directory of where the excel workbook is located
' Application.ActiveWorkbook.FullName for the path with the workbook name.

myFile = Dir(myPath & "*.*") 'I would place ".pdf" for pdf files only

r = 10 'row 10 is initial row where the current file names will be placed

'Cleaning the Current File Name Cells
ActiveSheet.Range("$A$10:$A$35").Clear

Do While myFile <> "" 'runs until there is no more myFile type files
    Cells(r, 1).Value = myFile
    r = r + 1
    myFile = Dir
Loop

End Sub

Sub RenameFiles()

Dim myPath As String

myPath = Application.ActiveWorkbook.Path & "\Files to change name\"
r = 10 'row 10 is initial row where the current and new file names are placed
Do Until IsEmpty(Cells(r, 1)) And IsEmpty(Cells(r, 2))
    Name myPath & Cells(r, 1).Value As myPath & Cells(r, 2).Value 'changing the files names
    r = r + 1
    

Loop



End Sub

Sub MoveFiles()

Dim SourceFileDir As String
Dim FileName As String
Dim SourceFileName As String
Dim DestinFileDir As String
Dim DestinFileName As String

Dim File As Object


'creating the object
Set File = CreateObject("Scripting.Filesystemobject")

SourceFileDir = Application.ActiveWorkbook.Path & "\Files to change name\"
FileName = Dir(SourceFileDir & "*.*") 'I would place ".pdf" for pdf files only

DestinFileDir = "C:\The Destination Folder\"

Do While FileName <> ""
    SourceFileName = SourceFileDir & FileName
    DestinFileName = DestinFileDir & FileName
    File.MoveFile Source:=SourceFileName, Destination:=DestinFileName
    MsgBox ("The file " + FileName + " was moved to " + DestinFileDir) 'pop up box with message to the user
    FileName = Dir
Loop


End Sub


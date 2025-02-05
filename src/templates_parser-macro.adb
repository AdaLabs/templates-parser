------------------------------------------------------------------------------
--                             Templates Parser                             --
--                                                                          --
--                     Copyright (C) 2010-2024, AdaCore                     --
--                                                                          --
--  This library is free software;  you can redistribute it and/or modify   --
--  it under terms of the  GNU General Public License  as published by the  --
--  Free Software  Foundation;  either version 3,  or (at your  option) any --
--  later version. This library is distributed in the hope that it will be  --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                    --
--                                                                          --
--  As a special exception under Section 7 of GPL version 3, you are        --
--  granted additional permissions described in the GCC Runtime Library     --
--  Exception, version 3.1, as published by the Free Software Foundation.   --
--                                                                          --
--  You should have received a copy of the GNU General Public License and   --
--  a copy of the GCC Runtime Library Exception along with this program;    --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see   --
--  <http://www.gnu.org/licenses/>.                                         --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash_Case_Insensitive;
with Ada.Text_IO;

separate (Templates_Parser)

package body Macro is

   function Default_Callback
     (Name : String; Params : Parameter_Set) return String;
   --  Default macro callback

   package Registry is new Containers.Indefinite_Hashed_Maps
     (String, Tree, Strings.Hash_Case_Insensitive, "=");

   Set : Registry.Map;

   ----------------------
   -- Default_Callback --
   ----------------------

   function Default_Callback
     (Name : String; Params : Parameter_Set) return String
   is
      function Parameters return String;
      --  Returns parameters

      ----------------
      -- Parameters --
      ----------------

      function Parameters return String is
         R : Unbounded_String;
      begin
         for K in Params'Range loop
            Append (R, Params (K));

            if K /= Params'Last then
               Append (R, ",");
            end if;
         end loop;

         return To_String (R);
      end Parameters;

   begin
      return To_String (Begin_Tag) & Name
        & "(" & Parameters & ")" & To_String (End_Tag);
   end Default_Callback;

   ---------
   -- Get --
   ---------

   function Get (Name : String) return Tree is
      Position : constant Registry.Cursor := Set.Find (Name);
   begin
      if Registry.Has_Element (Position) then
         return Registry.Element (Position);
      else
         return null;
      end if;
   end Get;

   --------------------------
   -- Print_Defined_Macros --
   --------------------------

   procedure Print_Defined_Macros is
   begin
      Text_IO.Put_Line ("------------------------------------- MACROS");

      for C in Set.Iterate loop
         declare
            Name  : constant String := Registry.Key (C);
            Macro : constant Tree := Registry.Element (C);
         begin
            Text_IO.Put_Line ("[MACRO] " & Name);
            Print_Tree (Macro);
            Text_IO.Put_Line ("[END_MACRO]");
            Text_IO.New_Line;
         end;
      end loop;
   end Print_Defined_Macros;

   --------------
   -- Register --
   --------------

   procedure Register (Name : String; T : not null Tree) is
      Old : Tree := Get (Name);
   begin
      if Old /= null then
         Set.Delete (Name);
         Release (Old);
      end if;

      Set.Insert (Name, T);
   end Register;

   -------------
   -- Rewrite --
   -------------

   procedure Rewrite
     (T          : in out Tree;
      Parameters : not null access Data.Parameter_Set)
   is
      use type Definitions.Tree;

      procedure Rewrite_Tree
        (T          : in out Tree;
         Parameters : not null access Data.Parameter_Set);
      --  Recursivelly rewrite the whole tree

      package Set_Var is new Containers.Indefinite_Hashed_Maps
        (String, Definitions.Tree, Strings.Hash_Case_Insensitive, "=");

      procedure Release_Definition (Position : Set_Var.Cursor);
      --  Release definition tree pointed to by Position

      Vars : Set_Var.Map;

      ------------------------
      -- Release_Definition --
      ------------------------

      procedure Release_Definition (Position : Set_Var.Cursor) is
         E : Definitions.Tree := Set_Var.Element (Position);
      begin
         Definitions.Release (E);
      end Release_Definition;

      ------------------
      -- Rewrite_Tree --
      ------------------

      procedure Rewrite_Tree
        (T          : in out Tree;
         Parameters : not null access Data.Parameter_Set)
      is
         procedure Rewrite (T : in out Data.Tree);
         --  Rewrite every variable references @_$N_@ (where N is a
         --  number) by the corresponding variable or value found in
         --  Parameters(N) or by the corresponding variable mapping in Vars.

         procedure Rewrite (T : in out Expr.Tree);
         --  Rewrite condition.
         --  In @@IF@@ @_$N_@ = val
         --  Replace $N by Parameters(N) or by the corresponding value in the
         --  variable mapping or does nothing if Parameters(N) does not exist
         --  or no variable mapping found.

         procedure Rewrite (Included : in out Included_File_Info);
         --  Process included files (from @@INCLUDE@@ or @@EXTENDS@@)

         -------------
         -- Rewrite --
         -------------

         procedure Rewrite (T : in out Data.Tree) is

            procedure Replace
              (T, C, Prev : in out Data.Tree; Ref : Positive);
            --  Replace node C with the parameters pointed to by Ref

            procedure Replace
              (T, C, Prev : in out Data.Tree; Value : String);
            --  As above, but replace by Value

            procedure Delete_Node (T : in out Data.Tree; C, Prev : Data.Tree);
            --  Delete node C

            -----------------
            -- Delete_Note --
            -----------------

            procedure Delete_Node
              (T : in out Data.Tree; C, Prev : Data.Tree)
            is
               use type Data.Tree;
               Old : Data.Tree;
            begin
               if Prev = null then
                  Old := T;
                  T := C.Next;
               else
                  Old := C;
                  Prev.Next := C.Next;
               end if;

               Data.Release (Old, Single => True);
            end Delete_Node;

            -------------
            -- Replace --
            -------------

            procedure Replace
              (T, C, Prev : in out Data.Tree; Ref : Positive)
            is
               use type Data.Tree;
               New_Node : constant Data.Tree := Data.Clone (Parameters (Ref));
            begin
               New_Node.Next := C.Next;

               if Prev = null then
                  Data.Release (T, Single => True);
                  T := New_Node;
               else
                  Data.Release (Prev.Next, Single => True);
                  Prev.Next := New_Node;
               end if;

               Prev := New_Node;
               C := New_Node.Next;
            end Replace;

            procedure Replace
              (T, C, Prev : in out Data.Tree; Value : String)
            is
               use type Data.Tree;
               New_Node : constant Data.Tree :=
                            new Data.Node'
                              (Data.Text,
                               Line  => C.Line,
                               Col   => Value'First,
                               Next  => C.Next,
                               Value => To_Unbounded_String (Value));
            begin
               if Prev = null then
                  Data.Release (T, Single => True);
                  T := New_Node;
               else
                  Data.Release (Prev.Next, Single => True);
                  Prev.Next := New_Node;
               end if;

               Prev := New_Node;
               C := New_Node.Next;
            end Replace;

            use type Data.Tree;
            D, Prev : Data.Tree;
            Moved   : Boolean := False;

         begin
            D    := T;
            Prev := null;

            while D /= null loop
               case D.Kind is
                  when Data.Text =>
                     null;

                  when Data.Var =>
                     --  Rewrite also the macro call if any

                     if D.Var.Is_Macro then
                        Rewrite_Tree (D.Var.Def, Parameters);

                     else
                        if D.Var.N > 0 then
                           --  This is a reference to a parameter

                           if D.Var.N <= Parameters'Length
                             and then Parameters (D.Var.N) /= null
                           then
                              --  This is a reference to replace
                              Replace (T, D, Prev, D.Var.N);

                           else
                              --  This variable does not have reference, remove
                              --  it.
                              Delete_Node (T, D, Prev);

                              D := D.Next;
                           end if;

                           Moved := True;

                        elsif Vars.Contains (To_String (D.Var.Name)) then
                           --  This is a variable that exists into the map.
                           --  It means that this variable is actually the
                           --  name of a SET which actually has been passed
                           --  a reference to another variable.

                           declare
                              E : constant Definitions.Tree :=
                                    Vars.Element (To_String (D.Var.Name));
                           begin
                              case E.N.Kind is
                                 when Definitions.Const =>
                                    Replace
                                      (T, D, Prev, To_String (E.N.Value));

                                 when Definitions.Ref =>
                                    if E.N.Ref <= Parameters'Length
                                      and then Parameters (E.N.Ref) /= null
                                    then
                                       Replace (T, D, Prev, E.N.Ref);
                                    else
                                       Replace (T, D, Prev, "");
                                    end if;

                                 when Definitions.Ref_Default =>
                                    if E.N.Ref <= Parameters'Length
                                      and then Parameters (E.N.Ref) /= null
                                    then
                                       Replace (T, D, Prev, E.N.Ref);
                                    else
                                       Replace
                                         (T, D, Prev, To_String (E.N.Value));
                                    end if;
                              end case;
                           end;

                           Moved := True;
                        end if;
                     end if;
               end case;

               if Moved then
                  Moved := False;
               else
                  Prev := D;
                  D    := D.Next;
               end if;
            end loop;
         end Rewrite;

         -------------
         -- Rewrite --
         -------------

         procedure Rewrite (T : in out Expr.Tree) is
            use type Data.Tree;

            procedure Replace (T : in out Expr.Tree; Ref : Positive)
              with Inline;
            --  Replace T with the parameters pointed to by Ref

            procedure Replace (T : in out Expr.Tree; Value : String)
              with Inline;
            --  Replace the node by the given value

            -------------
            -- Replace --
            -------------

            procedure Replace (T : in out Expr.Tree; Value : String) is
               Ctx     : aliased Filter.Filter_Context (0);
               N_Value : constant String :=
                           Data.Translate
                             (T.Var, Value, Ctx'Access);
               Line    : constant Natural := T.Line;
            begin
               Expr.Release (T, Single => True);
               T := new Expr.Node'
                 (Expr.Value, Line, V => To_Unbounded_String (N_Value));
            end Replace;

            procedure Replace (T : in out Expr.Tree; Ref : Positive) is
               Ctx     : aliased Filter.Filter_Context (0);
               Tag_Var : Data.Tag_Var;
            begin
               case Parameters (Ref).Kind is
                  when Data.Text =>
                     --  We need to evaluate the value against the filters
                     Replace
                       (T,
                        Data.Translate
                          (T.Var,
                           To_String (Parameters (Ref).Value),
                           Ctx'Access));

                  when Data.Var =>
                     Tag_Var := Data.Clone (Parameters (Ref).Var);
                     Data.Release (T.Var);
                     T.Var := Tag_Var;
               end case;
            end Replace;

         begin
            case T.Kind is
               when Expr.Value =>
                  null;

               when Expr.Var =>
                  if T.Var.N > 0 then
                     if T.Var.N <= Parameters'Length
                       and then Parameters (T.Var.N) /= null
                     then
                        --  This is a reference to replace
                        Replace (T, T.Var.N);
                     else
                        --  Referencing a parameter that does not exist
                        Replace (T, "");
                     end if;

                  elsif Vars.Contains (To_String (T.Var.Name)) then
                     --  This is a variable that exists in the map.
                     --  It means that this variable is actually the
                     --  name of a SET which actually has been passed
                     --  a reference to another variable.
                     declare
                        E : constant Definitions.Tree :=
                              Vars.Element (To_String (T.Var.Name));
                     begin
                        case E.N.Kind is
                           when Definitions.Const =>
                              Replace (T, To_String (E.N.Value));

                           when Definitions.Ref =>
                              if E.N.Ref <= Parameters'Length
                                and then Parameters (E.N.Ref) /= null
                              then
                                 Replace (T, E.N.Ref);
                              else
                                 Replace (T, "");
                              end if;

                           when Definitions.Ref_Default =>
                              null;
                        end case;
                     end;

                  else
                     --  Preserve the node as it is. It is likely refering to a
                     --  variable that was defined outside of the macro.
                     null;
                  end if;

               when Expr.Op =>
                  Rewrite (T.Left);
                  Rewrite (T.Right);

               when Expr.U_Op =>
                  Rewrite (T.Next);
            end case;
         end Rewrite;

         -------------
         -- Rewrite --
         -------------

         procedure Rewrite (Included : in out Included_File_Info) is
         begin
            for K in Included.Params'Range loop
               declare
                  use type Data.NKind;
                  use type Data.Tree;

                  procedure Set_Param (D : Data.Tree);
                  --  Set current include parameter to D

                  procedure Set_Param (I : Positive);
                  --  Set current include parameter to Parameters (I)

                  ---------------
                  -- Set_Param --
                  ---------------

                  procedure Set_Param (D : Data.Tree) is
                     Old : Data.Tree := Included.Params (K);
                  begin
                     Included.Params (K) := D;
                     Data.Release (Old);
                  end Set_Param;

                  procedure Set_Param (I : Positive) is
                  begin
                     Set_Param (Data.Clone (Parameters (I)));
                  end Set_Param;

                  P : Data.Tree renames Included.Params (K);

               begin
                  if P /= null and then P.Kind = Data.Var then
                     if P.Var.N > 0
                       and then P.Var.N <= Parameters'Last
                     then
                        Set_Param (P.Var.N);

                     elsif Vars.Contains (To_String (P.Var.Name)) then
                        declare
                           use type Definitions.NKind;

                           E : constant Definitions.Tree :=
                                 Vars.Element (To_String (P.Var.Name));
                        begin
                           if E.N.Kind = Definitions.Ref then
                              Set_Param (E.N.Ref);
                           end if;
                        end;
                     end if;
                  end if;
               end;
            end loop;
         end Rewrite;

         N     : Tree := T;
         Prev  : Tree;
         Moved : Boolean := False;

      begin
         T := N;

         while N /= null loop
            case N.Kind is
               when Text =>
                  Rewrite (N.Text);

               when If_Stmt =>
                  Rewrite (N.Cond);
                  Rewrite_Tree (N.N_True, Parameters);
                  Rewrite_Tree (N.N_False, Parameters);

               when Set_Stmt =>
                  --  Record definition and delete node, note that the
                  --  defintion tree will be freed later as we need the tree
                  --  for the rewriting.

                  Vars.Include (To_String (N.Def.Name), N.Def);

                  declare
                     Old : Tree := N;
                  begin
                     if Prev = null then
                        T := N.Next;
                        N := T;
                     else
                        Prev.Next := N.Next;
                        N := Prev.Next;
                     end if;

                     Unchecked_Free (Old);

                     Moved := True;
                  end;

               when Table_Stmt =>
                  Rewrite_Tree (N.Blocks, Parameters);

               when Section_Block =>
                  Rewrite_Tree (N.Common, Parameters);
                  Rewrite_Tree (N.Sections, Parameters);

               when Section_Stmt =>
                  Rewrite_Tree (N.N_Section, Parameters);

               when Include_Stmt =>
                  Rewrite (N.I_Included);

               when Inline_Stmt =>
                  Rewrite_Tree (N.I_Block, Parameters);

               when Extends_Stmt =>
                  Rewrite (N.E_Included);
                  Rewrite_Tree (N.N_Extends, Parameters);

               when Block_Stmt =>
                  Rewrite_Tree (N.N_Block, Parameters);

               when Info | C_Info =>
                  null;
            end case;

            if Moved then
               Moved := False;
            else
               Prev := N;
               N := N.Next;
            end if;
         end loop;
      end Rewrite_Tree;

   begin
      Rewrite_Tree (T, Parameters);

      Vars.Iterate (Release_Definition'Access);
   end Rewrite;

begin
   Callback := Default_Callback'Access;
end Macro;

(* 
   Copyright (C) 2012 Microsoft Corporation
   Author: CM Wintersteiger (cwinter) 2012-12-17
*)

open Z3
open Z3.Symbol
open Z3.Sort
open Z3.Expr
open Z3.Boolean
open Z3.FuncDecl
open Z3.Goal
open Z3.Tactic
open Z3.Tactic.ApplyResult
open Z3.Probe
open Z3.Solver
open Z3.Arithmetic
open Z3.Arithmetic.Integer
open Z3.Arithmetic.Real
open Z3.BitVector

exception TestFailedException of string

(**
   Model Converter test
*)
let  model_converter_test ( ctx : context ) =
  Printf.printf "ModelConverterTest\n";
  let xr = (arith_expr_of_expr 
	      (Expr.mk_const ctx (Symbol.mk_string ctx "x") 
		 (sort_of_arith_sort (arith_sort_of_real_sort (Real.mk_sort ctx))))) in
  let yr =  (arith_expr_of_expr
	       (Expr.mk_const ctx (Symbol.mk_string ctx "y") 
		  (sort_of_arith_sort (arith_sort_of_real_sort (Real.mk_sort ctx))))) in
  let g4 = (mk_goal ctx true false false ) in
  (Goal.assert_ g4 [| (mk_gt ctx xr 
			 (arith_expr_of_real_expr (real_expr_of_rat_num 
						     (Real.mk_numeral_nd ctx 10 1)))) |]) ;
  (Goal.assert_ g4 [| (mk_eq ctx 
			 (expr_of_arith_expr yr) 
			 (expr_of_arith_expr (Arithmetic.mk_add ctx [| xr; (arith_expr_of_real_expr (real_expr_of_rat_num (Real.mk_numeral_nd ctx 1 1)))  |]) ) ) |] ) ;
  (Goal.assert_ g4 [| (mk_gt ctx yr (arith_expr_of_real_expr (real_expr_of_rat_num (Real.mk_numeral_nd ctx 1 1)))) |]) ;
  (
    let  ar = (Tactic.apply (mk_tactic ctx "simplify") g4 None) in
    if ((get_num_subgoals ar) == 1 && 
	   ((is_decided_sat (get_subgoal ar 0)) ||  
	       (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
  );
  (
    let ar = (Tactic.apply (and_then ctx (mk_tactic ctx ("simplify")) (mk_tactic ctx "solve-eqs") [||]) g4 None) in
    if ((get_num_subgoals ar) == 1 && 
	   ((is_decided_sat (get_subgoal ar 0)) ||  
	       (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
    ;
    let solver = (mk_solver ctx None) in
    let f e = (Solver.assert_ solver [| e |]) in
    ignore (Array.map f (get_formulas (get_subgoal ar 0))) ;
    let q = (check solver [||]) in
    if q != SATISFIABLE then 
      raise (TestFailedException "")
    else
      let m = (get_model solver) in    
      match m with 
	| None -> raise (TestFailedException "")
	| Some (m) -> 
	  Printf.printf "Solver says: %s\n" (string_of_status q) ;
	  Printf.printf "Model: \n%s\n" (Model.to_string m) ;
	  Printf.printf "Converted Model: \n%s\n" (Model.to_string (convert_model ar 0 m))
  )

(**
 Some basic tests.
*)
let basic_tests ( ctx : context ) =
  Printf.printf "BasicTests\n" ;
(*  let qi = (mk_int ctx 1) in *)
  let fname = (mk_string ctx "f") in
  let x = (mk_string ctx "x") in
  let y = (mk_string ctx "y") in
  let bs = (sort_of_bool_sort (Boolean.mk_sort ctx)) in
  let domain = [| bs; bs |] in
  let f = (FuncDecl.mk_func_decl ctx fname domain bs) in
  let fapp = (mk_app ctx f 
		[| (Expr.mk_const ctx x bs); (Expr.mk_const ctx y bs) |]) in
  let fargs2 = [| (mk_fresh_const ctx "cp" bs) |] in
  let domain2 = [| bs |] in
  let fapp2 = (mk_app ctx (mk_fresh_func_decl ctx "fp" domain2 bs) fargs2) in
  let trivial_eq = (mk_eq ctx fapp fapp) in
  let nontrivial_eq = (mk_eq ctx fapp fapp2) in
  let g = (mk_goal ctx true false false) in
  (Goal.assert_ g [| trivial_eq |]) ;
  (Goal.assert_ g [| nontrivial_eq |]) ;
  Printf.printf "%s\n" ("Goal: " ^ (Goal.to_string g)) ;
  (
    let solver = (mk_solver ctx None) in
    (Array.iter (fun a -> (Solver.assert_ solver [| a |])) (get_formulas g)) ;
    if (check solver [||]) != SATISFIABLE then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
  );
  (
    let ar = (Tactic.apply (mk_tactic ctx "simplify") g None) in
    if ((get_num_subgoals ar) == 1 && 
	   ((is_decided_sat (get_subgoal ar 0)) ||  
	       (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
  );
  (
    let ar = (Tactic.apply (mk_tactic ctx "smt") g None) in
    if ((get_num_subgoals ar) == 1 && 
	   (not (is_decided_sat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
  );
  (Goal.assert_ g [| (mk_eq ctx 
			(mk_numeral_int ctx 1 
			   (sort_of_bitvec_sort (BitVector.mk_sort ctx 32)))
			(mk_numeral_int ctx 2 
			   (sort_of_bitvec_sort (BitVector.mk_sort ctx 32)))) |] )
  ;
  (
    let ar = (Tactic.apply (mk_tactic ctx "smt") g None) in
    if ((get_num_subgoals ar) == 1 && 
	   (not (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else 
      Printf.printf "Test passed.\n"
  );
  (
    let g2 = (mk_goal ctx true true false) in
    let ar = (Tactic.apply (mk_tactic ctx "smt") g2 None) in
    if ((get_num_subgoals ar) == 1 && 
	   (not (is_decided_sat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else
      Printf.printf "Test passed.\n"
  );
  (
    let g2 = (mk_goal ctx true true false) in
    (Goal.assert_ g2 [| (Boolean.mk_false ctx) |]) ;
    let ar = (Tactic.apply (mk_tactic ctx "smt") g2 None) in
    if ((get_num_subgoals ar) == 1 && 
	   (not (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else 
      Printf.printf "Test passed.\n"
  );
  (
    let g3 = (mk_goal ctx true true false) in
    let xc = (Expr.mk_const ctx (Symbol.mk_string ctx "x") (sort_of_arith_sort (arith_sort_of_int_sort (Integer.mk_sort ctx)))) in
    let yc = (Expr.mk_const ctx (Symbol.mk_string ctx "y") (sort_of_arith_sort (arith_sort_of_int_sort (Integer.mk_sort ctx)))) in
    (Goal.assert_ g3 [| (mk_eq ctx xc (mk_numeral_int ctx 1 (sort_of_arith_sort (arith_sort_of_int_sort (Integer.mk_sort ctx))))) |]) ;
    (Goal.assert_ g3 [| (mk_eq ctx yc (mk_numeral_int ctx 2 (sort_of_arith_sort (arith_sort_of_int_sort (Integer.mk_sort ctx))))) |]) ;
    let constr = (mk_eq ctx xc yc) in
    (Goal.assert_ g3 [| constr |] ) ;
    let ar = (Tactic.apply (mk_tactic ctx "smt") g3 None) in
    if ((get_num_subgoals ar) == 1 && 
	   (not (is_decided_unsat (get_subgoal ar 0)))) then
      raise (TestFailedException "")
    else 
      Printf.printf "Test passed.\n"
  ) ;
  model_converter_test ctx
(*
            // Real num/den test.
            RatNum rn = ctx.MkReal(42, 43);
            Expr inum = rn.Numerator;
            Expr iden = rn.Denominator;
            Console.WriteLine("Numerator: " + inum + " Denominator: " + iden);
            if (inum.ToString() != "42" || iden.ToString() != "43")
                throw new TestFailedException();

            if (rn.ToDecimalString(3) != "0.976?")
                throw new TestFailedException();

            BigIntCheck(ctx, ctx.MkReal("-1231231232/234234333"));
            BigIntCheck(ctx, ctx.MkReal("-123123234234234234231232/234234333"));
            BigIntCheck(ctx, ctx.MkReal("-234234333"));
            BigIntCheck(ctx, ctx.MkReal("234234333/2"));


            string bn = "1234567890987654321";

            if (ctx.MkInt(bn).BigInteger.ToString() != bn)
                throw new TestFailedException();

            if (ctx.MkBV(bn, 128).BigInteger.ToString() != bn)
                throw new TestFailedException();

            if (ctx.MkBV(bn, 32).BigInteger.ToString() == bn)
                throw new TestFailedException();

            // Error handling test.
            try
            {
                IntExpr i = ctx.MkInt("1/2");
                throw new TestFailedException(); // unreachable
            }
            catch (Z3Exception)
            {
            }
        }
*)


let _ = 
  if not (Log.open_ "z3.log") then
    raise (TestFailedException "Log couldn't be opened.")
  else
    (
      Printf.printf "Running Z3 version %s\n" Version.to_string ;
      let cfg = [("model", "true"); ("proof", "false")] in
      let ctx = (mk_context cfg) in
      let is = (Symbol.mk_int ctx 42) in
      let ss = (Symbol.mk_string ctx "mySymbol") in
      let bs = (Boolean.mk_sort ctx) in
      let ints = (Integer.mk_sort ctx) in
      let rs = (Real.mk_sort ctx) in
      Printf.printf "int symbol: %s\n" (Symbol.to_string is);
      Printf.printf "string symbol: %s\n" (Symbol.to_string ss);
      Printf.printf "bool sort: %s\n" (Sort.to_string (sort_of_bool_sort bs));
      Printf.printf "int sort: %s\n" (Sort.to_string (sort_of_arith_sort (arith_sort_of_int_sort ints)));
      Printf.printf "real sort: %s\n" (Sort.to_string (sort_of_arith_sort (arith_sort_of_real_sort rs)));
      basic_tests ctx ;
      Printf.printf "Disposing...\n";
      Gc.full_major ()
    );
  Printf.printf "Exiting.\n";
;;

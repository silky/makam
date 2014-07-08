(*

The Makam metalanguage -- a tool for rapid language prototyping
Copyright (C) 2011- Antonis Stampoulis

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*)

open Utils;;
open Batteries;;
open Termlangcanon;;
open Termlangbuiltin;;
open Termlangprolog;;


let new_builtin_predicate_from_functions s t fs =
  let open RunCtx.Monad in
  let isMeta p = match p.term with `LamMany(_, { term = `Meta(_) }) -> true | _ -> false in
  new_builtin_predicate s t
  (fun _ -> fun args -> perform
    args' <-- mapM (chasePattcanon ~deep:true []) args ;
    let f, args, meta = 
      let n = List.length args' in
      try
	let (prev, meta, next), i = ExtList.find_partition_index isMeta args' in
	let f = List.nth fs i in
	f, prev ++ next, meta
      with ExtList.NotFoundPartition ->
	List.nth fs (n-1), List.take (n-1) args', List.last args'
    in
    res <-- f args ;
    pattcanonUnifyFull meta res)
;;

let _totypinfo t = { term = () ; classifier = t ; loc = None ; extra = DummyExtras.empty () } ;;

let _PtoString (s : pattcanon) = let open RunCtx.Monad in match s.term with `LamMany( _, { term = `AppMany( { term = `Const(o) }, _, _) } ) -> return (Obj.obj o) | _ -> mzero ;;
let _PofString ?(loc = None) s : pattcanon = pattcanonString s ~loc:loc ;;

let _PtoInt (s : pattcanon) : int RunCtx.Monad.m = let open RunCtx.Monad in match s.term with `LamMany( _, { term = `AppMany( { term = `Const(o) }, _, _) } ) -> return (Obj.obj o) | _ -> mzero ;;
let _PofInt ?(loc = None) i : pattcanon = pattcanonInt i ~loc:loc ;;

let _PtoList  (xs : pattcanon) : pattcanon list RunCtx.Monad.m =
  let open RunCtx.Monad in
  let rec aux s acc = 
    perform
    s <-- chasePattcanon [] s ;
    match s.term with
      `LamMany([], { term = `AppMany( { term = `Var(_, (`Free, idx)) }, [], _) }) when idx = _eiNil ->
	return (List.rev acc)
    | `LamMany([], { term = `AppMany( { term = `Var(_, (`Free, idx)) }, [ hd ; tl ], _) }) when idx = _eiCons ->
        aux tl (hd :: acc)
    | _ -> mzero
  in
  aux xs []
;;
let _PofList ?(loc = None) (t : typ) (xs : pattcanon list) : pattcanon =
  let open RunCtx.Monad in
  let nil : pattcanon = { classifier = _tList t ; loc = loc ; term = `Var( `Concrete("nil"), (`Free, _eiNil) ) ;
			  extra = PattExtras.empty () } |> pattheadToCanon
  in
  let conshead : patthead = { term = `Var( `Concrete("cons"), (`Free, _eiCons) ) ; classifier = t **> _tList t **> _tList t ; loc = loc ; extra = PattExtras.empty () } in
  let cons hd tl : pattcanon = 
    let neut = 
      { classifier = _tList t ; loc = loc ;
	term = `AppMany( conshead, [ hd ; tl ], [ _tList t **> _tList t |> _totypinfo ; _tList t |> _totypinfo ] ) ;
	extra = PattExtras.empty () }
    in
    { classifier = _tList t ; loc = loc ;
      term = `LamMany([], neut) ; extra = PattExtras.empty () }
  in
  List.fold_right cons xs nil
;;

let _PtoBool (x : pattcanon) : bool RunCtx.Monad.m =
  let open RunCtx.Monad in
   perform
     x <-- chasePattcanon [] x ;
     match x.term with
	 `LamMany([], { term = `AppMany( { term = `Var(_, (`Free, idx)) }, [], _) }) when idx = _eiTrue -> return true
       | `LamMany([], { term = `AppMany( { term = `Var(_, (`Free, idx)) }, [], _) }) when idx = _eiFalse -> return false
;;

let _PofBool ?(loc = None) (x : bool) : pattcanon =
  let open RunCtx.Monad in
  let ptrue : pattcanon = { classifier = _tBool ; loc = loc ;
			    term = `Var( `Concrete("true"), (`Free, _eiTrue) ) ;
			    extra = PattExtras.empty () } |> pattheadToCanon
  in
  let pfals : pattcanon = { classifier = _tBool ; loc = loc ;
			    term = `Var( `Concrete("false"), (`Free, _eiFalse) ) ;
			    extra = PattExtras.empty () } |> pattheadToCanon
  in
  if x then ptrue else pfals
;;

let _PtoDyn (d : pattcanon) (t : typ) : pattcanon RunCtx.Monad.m = 
  let open RunCtx.Monad in
  match d.term with
      `LamMany([], { term = `AppMany( { term = `Var(_, (`Free, idx)) }, [ term ], _) }) when idx = _eiDyn ->
	perform
	  b <-- inmonad ~statewrite:true (fun _ -> typUnifyBool t term.classifier) ;
	  moneOrMzero b ;
	  return term
    | _ -> mzero
;;

let _PofDyn ?(loc = None) (x : pattcanon) : pattcanon =
  let open RunCtx.Monad in
  let t = x.classifier in
  let dynhead : patthead = { term = `Var(`Concrete("dyn"), (`Free, _eiDyn)); classifier = t **> _tDyn ; loc = loc ; extra = PattExtras.empty () } in
  let dyn e : pattcanon =
    let neut =
      { classifier = _tDyn ; loc = loc ; extra = PattExtras.empty () ;
	term = `AppMany(dynhead, [ e ], [ _tDyn |> _totypinfo ]) }
    in
    { classifier = _tDyn ; loc = loc ; extra = PattExtras.empty () ;
      term = `LamMany([], neut) }
  in
  dyn x
;;
    
(* ---------
   Integers.
   --------- *)
new_builtin_predicate_from_functions "plus" ( _tInt **> _tInt **> _tInt **> _tProp ) begin
  let open RunCtx.Monad in
  let convertfunc f [ i1 ; i2 ] = 
    perform
      i1' <-- _PtoInt i1 ;
      i2' <-- _PtoInt i2 ;
      let res = f i1' i2' in
      return (_PofInt res ~loc:i1.loc)
  in
  [ (* Meta, Const, Const *)
    convertfunc (fun b res -> res - b);

    (* Const, Meta, Const *)
    convertfunc (fun a res -> res - a);

    (* Const, Const, Meta *)
    convertfunc (fun a b -> a + b) ]
end;;

new_builtin_predicate_from_functions "mult" ( _tInt **> _tInt **> _tInt **> _tProp ) begin
  let open RunCtx.Monad in
  let convertfunc f [ i1 ; i2 ] = 
    perform
      i1' <-- _PtoInt i1 ;
      i2' <-- _PtoInt i2 ;
      let res = try Some (f i1' i2') with _ -> None in
      match res with 
	  Some i -> return (_PofInt i ~loc:i1.loc)
	| None -> mzero
  in
  [ (* Meta, Const, Const *)
    convertfunc (fun b res -> res / b);

    (* Const, Meta, Const *)
    convertfunc (fun a res -> res / a);

    (* Const, Const, Meta *)
    convertfunc (fun a b -> a * b) ]
end;;

new_builtin_predicate "lessthan" ( _tInt **> _tInt **> _tBool **> _tProp ) begin

  let open RunCtx.Monad in
  let isMeta t = match t.term with `LamMany( _, { term = `Meta(_) } ) -> true | _ -> false in
  (fun _ -> fun [ i1; i2; res ] -> perform
    i1' <-- chasePattcanon [] i1 ;
    i2' <-- chasePattcanon [] i2 ;
    if isMeta i1' || isMeta i2' then mzero
    else (perform
	    i1'' <-- _PtoInt i1' ;
	    i2'' <-- _PtoInt i2' ;
	    pattcanonUnifyFull res (_PofBool (i1'' < i2'') ~loc:i1.loc)))
  
end;;
    
(* ---------
   Strings. 
   --------- *)
new_builtin_predicate_from_functions "append" ( _tString **> _tString **> _tString **> _tProp) begin
  let open RunCtx.Monad in
  let convertfunc f [ s1 ; s2 ] = 
    perform
      s1' <-- _PtoString s1 ;
      s2' <-- _PtoString s2 ;
      let res = f s1' s2' in
      match res with
	Some(s) -> return (_PofString s ~loc:s1.loc)
      | None -> mzero
  in
  [ (* Meta, Const, Const *)
    convertfunc (fun strTL strFULL ->
      if String.ends_with strFULL strTL then
	let strHD = String.sub strFULL 0 (String.length strFULL - String.length strTL) in
	Some strHD
      else
	None);

    (* Const, Meta, Const *)
    convertfunc (fun strHD strFULL ->
      if String.starts_with strFULL strHD then
	let strTL = String.sub strFULL (String.length strHD) (String.length strFULL - 1) in
	Some strTL
      else
	None) ;

    (* Const, Const, Meta *)
    convertfunc (fun strHD strTL -> Some (strHD ^ strTL)) ]
end
;;
      
new_builtin_predicate_from_functions "explode" (_tString **> _tList _tString **> _tProp) begin
  let open RunCtx.Monad in
  [ (function [ ls ] ->
      perform
	ls'  <-- _PtoList ls ;
        ls'' <-- mapM _PtoString ls' ;
	let s = String.concat "" ls'' in
	return (_PofString ~loc:ls.loc s));
    (function [ s ] ->
      perform
	s' <-- _PtoString s ;
        let span = match s.loc with Some { startloc = loc } -> Some loc | None -> None in
        let stream = UChannel.from_string ?initloc:span s' in
	let s'' = stream |> UChannel.map
	                    (fun chan c -> UString.implode [c] |> UString.to_string
				           |> _PofString ~loc:(UChannel.mk_span (UChannel.loc chan) (UChannel.loc chan)))
	in
	return (_PofList _tString s'' ~loc:s.loc)
    ) ]
end
;;


(* --------------
   Character classes. 
   -------------- *)
let _ = 
  let new_char_class s f =
    (let open RunCtx.Monad in
    let isMeta t = match t.term with `LamMany( _, { term = `Meta(_) } ) -> true | _ -> false in
    new_builtin_predicate s (_tString **> _tProp)
    (fun _ -> fun [ c ] -> perform
      c' <-- chasePattcanon ~deep:true [] c ;
      if isMeta c' then mzero
      else (perform
	      c'' <-- _PtoString c' ;
	      let c'' = UString.gethd (UString.of_string c'') in
	      moneOrMzero (f c''))))
  in
  new_char_class "char_latin1" (fun c -> try (ignore (UChar.char_of c); true) with _ -> false) ;
  new_char_class "char_letter" (fun c -> match UString.category c with
    | `Ll | `Lm | `Lo | `Lt | `Lu -> true | _ -> false)
;;


(* Printing. *)
new_builtin_predicate "print" ( ~* "A" **> _tProp )
  (fun _ -> fun [ e ] ->
    (let open RunCtx.Monad in
     perform
     e <-- pattcanonRenormalize e ;
     p <-- chasePattcanon ~deep:true [] e ;
     let _ = Printf.printf "%a\n%!" Pattcanon.alphaSanitizedPrint p in
     return ()))
;;

new_builtin_predicate "cheapprint" ( _tInt **> ~* "A" **> _tProp )
  (fun _ -> fun [ depth ; e ] ->
    (let open RunCtx.Monad in
     perform
     e <-- pattcanonRenormalize e ;
     p <-- chasePattcanon ~deep:true [] e ;
     depth <-- chasePattcanon ~deep:true [] depth ;
     depth <-- _PtoInt depth ;
     inmonad ~statewrite:false (fun _ -> Printf.printf "%a\n%!" (CheapPrint.canondepth depth) p);
     return ()))
;;

new_builtin_predicate "print_current_metalevel" ( _tProp )
  (fun _ -> fun [] ->
    (let open RunCtx.Monad in
     perform
       env <-- getenv;
       \ Printf.printf "current metalevel: %a\n" (List.print (Pair.print CheapPrint.name Typ.print)) env.renvars ;
       return ()))
;;


(* -------------
   Local debugging.
   ------------- *)
new_builtin_predicate "debug" ( _tProp  **> _tProp )
  (fun _ -> fun [ p ] ->
    let open RunCtx.Monad in
    perform
      _ <-- return () ;
      let prev = !_DEBUG_DEMAND in
      let _ = _DEBUG_DEMAND := true in
      let p = match p.term with `LamMany([], p) -> p | _ -> assert false in
      _ <-- ifte (try demand p with e -> (_DEBUG_DEMAND := prev; raise e))
	    (fun _ -> _DEBUG_DEMAND := prev; return ())
	    (lazy(perform
	       _ <-- return () ;
	       let _ = _DEBUG_DEMAND := prev in
	       mzero)) ;
      return ())
;;

new_builtin_predicate "trace" ( (~* "A") **> _tProp **> _tProp )
  (fun _ -> fun [ g ; cont ] ->
    let open RunCtx.Monad in
    perform

      g' <-- pattcanonRenormalize g;
      cont <-- pattcanonRenormalize cont ;
      let cont = match cont.term with `LamMany([], cont) -> cont | _ -> assert false in

      idx <--
	(match g'.term with
	    `LamMany(_, ({ classifier = { term = `TVar(_, tidx, _) } } as p))
	      when tidx = _tiProp ->
	      return (headPredicate p)
	  | _ -> mzero) ;

      oldval <-- inmonad (fun () -> isTraced_mutable idx) ;
      inmonad ~statewrite:true (fun () -> setTracedIndex_mutable true idx) ;

      ifte (try perform
		  r <-- demand cont ;
		  return (`Left r)
	    with e -> return (`Right e))
	   (fun res -> perform
	     inmonad ~statewrite:true (fun () -> setTracedIndex_mutable oldval idx) ;
	     return (reflectexn res))
	   (lazy(perform
		   inmonad ~statewrite:true (fun () -> setTracedIndex_mutable oldval idx) ;
		   mzero)))
;;


(* -------------
   Unification variables inspection.
   ------------- *)

let ensure_concrete_type (p : pattcanon) : unit RunCtx.Monad.m =
  let open RunCtx.Monad in
  perform
    t <-- intermlang (fun _ -> chaseType p.classifier) ;
    let b = match t.term with `TVar(_, Some (`Free, _), _) -> true | _ -> false in
    if b then return () else (Printf.printf "wrong call to external predicate expecting concrete type\n"; mzero)

;;

new_builtin_predicate "isunif" ( ~* "A" **> _tProp )
  (fun _ -> fun [ p ] ->
    (let open RunCtx.Monad in
     perform
       state  <-- getstate ;
       p      <-- chasePattcanon ~deep:true [] p ;
       _      <-- setstate state ;
       let isunif = match p.term with `LamMany(_, { term = `Meta _ }) -> true | _ -> false in
       moneOrMzero isunif))
;;

new_builtin_predicate "getunif" ( ~* "A" **> ~* "B" **> _tProp )
  (fun _ -> fun [ input ; output ] ->
    (let open RunCtx.Monad in
     let combine r1 r2 =
       match r1, r2 with
	 Some r, None | None, Some r -> Some r
       | Some (l1, u1), Some (l2, u2) -> if l1 < l2 then Some (l1, u1) else Some (l2, u2)
       | None, None -> None
     in
     let rec auxneut cur (p : pattneut) =
       match p.term with
	 `Meta(m1) ->
	   perform
	     ifte (perform
		     b <-- intermlang(fun _ -> typUnifyBool ~allow_instantiation:false p.classifier output.classifier) ;
	             moneOrMzero b)
	          (fun () -> perform
		     level <-- getMetaLevel (metaindex m1) ;
		     return (combine cur (Some (level, p))))
	          (lazy(foldM auxcanon cur (metasubstmain m1)))
       | `AppMany(hd, args, _) ->
	   foldM auxcanon cur args
     and auxcanon cur (p : pattcanon) =
       match p.term with
	 `LamMany(lamsinfo, p) -> auxneut cur p
     in
     perform
       _     <-- mapM ensure_concrete_type [ input ; output ] ;
       p     <-- chasePattcanon ~deep:true [] input ;
       p     <-- (match p.term with `LamMany([], p) -> return p | _ -> mzero) ;
       unif  <-- auxneut None p ;
       match unif, output.term with
	 Some (_, unif), `LamMany([], { term = `Meta(o) }) ->
	   (* pattUnifyFull output unif *)
	   setMetaParent (metaindex o) unif
       | _           -> mzero))
;;

new_builtin_predicate "absunif" ( ~* "A" **> ~* "B" **> (~* "B" **> ~* "A") **> _tProp )
  (fun _ [ term ; meta ; output ] ->
    (let open RunCtx.Monad in
     let getmetaindexcanon p = match p.term with `LamMany([], { term = `Meta(m) }) -> Some (metaindex m) | _ -> None in
     let getmetaindexneut p = match p.term with `Meta(m) -> Some (metaindex m) | _ -> None in
     let chaseWithConstraints uvar =
       let rec aux visited tovisit tovisit_set =
	 match tovisit with
	   [] -> return visited
	 | uvar :: tl when ISet.mem uvar visited -> aux visited tl (ISet.remove uvar tovisit_set)
	 | uvar :: tl ->
	   (perform 
	      let visited = ISet.add uvar visited in
	      let tovisit_set = ISet.remove uvar tovisit_set in
	      cs  <-- getConstraints uvar ;
	      cs' <-- mapM (fun elm ->
		            match elm with
		              `UnifCanon(bound, p1, p2) -> perform
				                             state <-- getbacktrackstate ;
				                             p1 <-- chasePattcanon bound p1 ;
				                             p2 <-- chasePattcanon bound p2 ;
							     setstate state ;
							     return (List.filter_map getmetaindexcanon [ p1 ; p2 ])
			    | `Unif(bound, p1, p2) -> perform
			                                state <-- getbacktrackstate ;
			                                p1 <-- chasePattneut bound p1 ;
							p2 <-- chasePattneut bound p2 ;
							setstate state ;
							return (List.filter_map getmetaindexneut [ p1 ; p2 ])
			    | _ -> return []) cs;
	      let cs' = List.flatten cs' in
	      let newones = List.filter (fun elm -> not (ISet.mem elm visited || ISet.mem elm tovisit_set)) cs' in
	      aux visited (newones ++ tl) (ISet.union (newones |> List.enum |> ISet.of_enum) tovisit_set))
       in
       aux ISet.empty [uvar] (ISet.singleton uvar)
     in
     let rec auxneut bound uvars p : pattneut =
       match p.term with
	 `Meta(m1) when ISet.mem (metaindex m1) uvars ->
	   let head = { p with term = `Var(`Anon, (`Bound, bound)) } in
	   let neut = { p with term = `AppMany(head, [], []) } in
	   neut
       | `Meta(s,idx,`Subst(subst,substinv,ts,names),t) ->
	 let subst = List.map (auxcanon bound uvars) subst in
	 let substinv = invertSubst subst in
	 { p with term = `Meta(s,idx,`Subst(subst,substinv,ts,names),t) }
       | `AppMany(hd, args, argsinfo) ->
	 { p with term = `AppMany(hd, List.map (auxcanon bound uvars) args, argsinfo) }
     and auxcanon bound uvars p : pattcanon =
       match p.term with
	 `LamMany(lamsinfo, body) -> { p with term = `LamMany(lamsinfo, auxneut (bound + List.length lamsinfo) uvars body) }
     in
     perform
       _    <-- mapM ensure_concrete_type [ term ; meta ] ;
       p    <-- chasePattcanon ~deep:true [] term ;
       meta <-- chasePattcanon ~deep:true [] meta ;
       uvar <-- (match getmetaindexcanon meta with Some i -> return i | _ -> mzero);
       uvars <-- chaseWithConstraints uvar ;
       p     <-- (match p.term with `LamMany([], p) -> return p | _ -> mzero) ;
       let ctx = auxneut 0 uvars p in
       let restyp = meta.classifier **> term.classifier in
       let res = { term = `LamMany( [ { term = (`Anon, meta.classifier) ; classifier = restyp ; loc = p.loc ; extra = PattExtras.empty () } ], ctx ) ;
		   classifier = restyp ;
		   loc = p.loc ; extra = PattExtras.empty () }
       in
       pattcanonUnifyFull output res))
;;

(* Findall. *)
(* -------- *)

(* TODO Warning: this is still unsafe, as it does not check for uninstantiated metas, so they could escape
   into the results *)
new_builtin_predicate "findall" ( ( ~* "A" **> _tProp) **> ((_tList (~* "A")) **> _tProp) )
  (let open RunCtx.Monad in
   fun _ -> fun [ pred ; res ] -> perform
      p' <-- pattcanonRenormalize pred ;
      p' <-- chasePattcanon [] p' ;
      (match p'.term with
	`LamMany( [ { term = name, typ } ], p'') ->
	  perform
	    newvar <-- addRunMeta None ;
	    state  <-- getbacktrackstate ;
	    let meta =
	      { term = `Meta("_"^(string_of_int newvar), newvar,
			     `Subst([], Some (IMap.empty, IMap.empty), [], []), typ ) ;
		classifier = typ ; loc = p'.loc ; extra = PattExtras.empty () }
	    in
	    let metacanon = { term = `LamMany( [], meta );
			     classifier = typ ; loc = p'.loc ; extra = PattExtras.empty () }
	    in
	    let subst' = [ metacanon ] in
	    let p'' = pattneutSubstMany subst' p'' in
	    results <-- getall (perform
		                  _   <-- demand p'' ;
				  res <-- chasePattcanon ~deep:true [] metacanon ;
				  setstate state ;
				  return res);
	    pattcanonUnifyFull res (_PofList typ results)
      | _ -> mzero))
;;



(* Locations. *)
(* ---------- *)
(* quite buggy for the time being *)

let _PtoLoc (s : pattcanon) : UChannel.span RunCtx.Monad.m = let open RunCtx.Monad in match s.term with `LamMany( _, { term = `AppMany( { term = `Const(o) }, _, _) } ) -> return (Obj.obj o) | _ -> mzero ;;
let _PofLoc ?(loc = None) s : pattcanon = pattcanonLoc s ~loc:loc ;;

new_builtin_predicate "locget" ( ~* "A" **> _tLoc **> _tProp)
  (let open RunCtx.Monad in
   fun _ -> fun [ which ; res ] -> perform
      which <-- pattcanonRenormalize which ;
      which <-- chasePattcanon [] which ;
      let loc = match which.term with `LamMany([], tm) -> tm.loc | _ -> which.loc in
      pattcanonUnifyFull res (_PofLoc loc))
;;

new_builtin_predicate "locset" ( ~* "A" **> _tLoc **> ~* "A" **> _tProp)
  (let open RunCtx.Monad in
   fun _ -> fun [ which ; loc ; res ] -> perform
      which <-- pattcanonRenormalize which ;
      which <-- chasePattcanon [] which ;
      loc   <-- chasePattcanon [] loc ;
      loc   <-- _PtoLoc loc ;
      let which' =
	match which.term with
	  `LamMany(lamsinfo, body) -> { which with term = `LamMany(lamsinfo, { body with loc = loc }) ; loc = loc }
      in
      pattcanonUnifyFull res which')
;;

	    


(*

let storedEnv () =
  let open RunCtx.Monad in
  let resolveAllMetas p =
    perform
      p <-- chasePatt ~deep:true [] p;
      _ <-- noUninstantiatedMetas p ;
      return p
  in
  let resolveAllMetasProp p =
    perform
      args' <-- mapM resolveAllMetas p.paargs ;
      return { p with paargs = args' }
  in
  let resolveAllMetasConstr (s, p) =
    perform
      p' <-- mapM resolveAllMetasProp p ;
      return (s, p')
  in
  perform
    env <-- getenv ;
    constrs <-- env.retemp_constr_goals |> Dict.bindings |> mapM resolveAllMetasConstr ;
    return { sevars = env.renvars ; seconstrs = constrs }
;;

define_external "storeenv" [] [ !@ "env" ] [ `Any ]
  (fun [] [ envres ] ->
    let open RunCtx.Monad in
    perform
      renv <-- storedEnv () ;
      pattUnifyFull envres { expr = `Const(Obj.repr renv) ; typ = !@ "env" ; loc = envres.loc })
;;

*)
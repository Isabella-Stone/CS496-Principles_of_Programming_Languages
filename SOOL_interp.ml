open Ast
open Ds

(* I pledge my honor that I have abided by the Stevens Honor System. *)
(* Ryan Giovanniello *)
(* Isabella Stone *)

(* params * body * super * fields *)
type method_decl = string list*Ast.expr*string*string list

type method_env = (string*method_decl) list

type class_decl = string*string list*method_env

type class_env = ((string*class_decl) list)
                 
(* Global holding the store *)
let g_store = Store.empty_store 20 (NumVal 0)

(* Global holding class declarations *)
let g_class_env : class_env ref = ref []


(* Helper functions for SOOL *)
    
(* 
 * Return all visible fields from class c_name 
 * Note: Should produce an error if the super class does not exist, this is pending  
*)
let rec get_fields =
  fun cs c_name class_decls ->
  match class_decls with
  | [] -> []
  | Class (name,super,fields,_methods)::_ when name=c_name ->
       fields :: get_fields cs super cs
  | Class (_,_,_,_)::cs' -> get_fields cs c_name cs'

(* 
 * Return all visible methods from class c_name 
 * Note: Should produce an error if the super class does not exist, this is pending  
*)
let rec get_methods cs c_name fss = function
  | [] -> []
  | Class (name,super,_fields,methods)::_ when name=c_name ->
    (List.map (fun (Method(n,pars,body))
               -> (n,(pars,body,super,List.flatten fss)))
methods) @ get_methods cs super (List.tl fss) cs
  | Class (_,_,_,_)::cs' -> get_methods cs c_name fss cs'
                                                
(* 
 * Initialize contents of g_class_env variable 
*)
let initialize_class_env cs = 
  let rec initialize_class_env' cs = function
    | [] -> ()
    | Class (name,super,fields,methods)::cs' ->
      let fss = fields :: get_fields cs super cs
      in let ms = (List.map (fun (Method(n,pars,body))
                              -> (n,(pars,body,super,List.flatten fss)))
                     methods) @ get_methods cs super (List.tl fss) cs
      in
      g_class_env := (name,(super,List.flatten fss,ms))::!g_class_env;
      initialize_class_env' cs cs'
  in g_class_env := [];
     initialize_class_env' cs cs

(* recursive helper for lookup_class to search entire environment and find correct class, 
then returns triple of (super,fields,methods) *)
let rec lookup_class_helper : string -> class_env -> class_decl ea_result  =
  fun c_name c_env ->
  match c_env with
  | (value, x)::t -> if value = c_name then return x
                     else lookup_class_helper c_name t
  | [] -> error "lookup_class: class c_name not found"

(* calls recursive helper *)
let lookup_class : string -> class_env -> class_decl ea_result  =
  fun c_name c_env ->
  lookup_class_helper c_name c_env

let slice fs env =
  (* print_string  @@ "Slicing:" ^String.concat "," fs
   *                  ^ "\n" ^ (string_of_env' env) ^"\n"; *)
  let rec slice' fs acc env =
    match fs, env with
    | [],_ -> acc
    | id::ids, ExtendEnv(id',ev,tail) when id=id' ->
      slice' ids (ExtendEnv(id',ev,acc)) tail
    | _,_ -> failwith @@ 
      "slice: ids different or lists have different lengths "
  in
  let new_env = (slice' (List.rev fs) EmptyEnv env) 
  in (* print_string @@ "Result is:" ^(string_of_env' new_env) ^"\n"; *)
  return new_env
    
(* recursive helper for new_env that builds environment with dummy value NumVal 0 *)
let rec new_env_helper : string list -> env ea_result  =
  fun fs ->
  match fs with
  | [] -> return EmptyEnv
  | x::t -> new_env_helper t >>+ extend_env x (RefVal (Store.new_ref g_store (NumVal 0)))

(* calls recursive helper *)
let new_env : string list -> env ea_result  =
  fun fs ->
  let revlist = List.rev fs in
  new_env_helper revlist

(* recursive helper that finds matching value of a tuple within a list of tuples *)
let rec lookup_method_helper =
    fun value list ->
    match list with
    | [] -> None
    | (a,b)::t -> if a = value then Some b
                  else lookup_method_helper value t

(* uses recursive lookup_method_helper to first get value linked with c_name in c_env, 
and then again to get value linked with m_name in methods *)
let lookup_method : string -> string -> class_env -> method_decl option =
  fun c_name m_name c_env -> 
    let x = (lookup_method_helper c_name c_env) in
    match x with 
    | Some (super, fields, methods) -> lookup_method_helper m_name methods
    | None -> None


let rec apply_method : string -> exp_val -> exp_val list ->
  method_decl -> exp_val ea_result =
  fun m_name self args (pars,body,super,fs) -> 
  let l = Store.new_ref g_store self
  and l_args = List.map (fun ev -> RefVal (Store.new_ref g_store ev)) args
  in let l' = Store.new_ref g_store (StringVal super)
  in
  if List.length args<> List.length pars
  then error (m_name ^": args and params have different lengths")
  else
  obj_of_objectVal self >>= fun  (_c_name,env) ->
  slice fs env >>+
  extend_env_list ("_super"::"_self"::pars) ((RefVal l')
                                                ::(RefVal l)::l_args) >>+
  eval_expr body 
and
  apply_clos : string*Ast.expr*env -> exp_val -> exp_val ea_result =
  fun (id,e,en) ev ->
  return en >>+
  extend_env id ev >>+
  eval_expr e
and
  eval_expr : expr -> exp_val ea_result =
  fun e ->
  match e with
  | Int(n) -> return @@ NumVal n
  | Var(id) -> 
    apply_env id >>=
    int_of_refVal >>= fun l ->
    Store.deref g_store l >>= fun ev ->
    return ev
  | Add(e1,e2) ->
    eval_expr e1 >>=
    int_of_numVal >>= fun n1 ->
    eval_expr e2 >>=
    int_of_numVal >>= fun n2 ->
    return @@ NumVal (n1+n2)
  | Sub(e1,e2) ->
    eval_expr e1 >>=
    int_of_numVal >>= fun n1 ->
    eval_expr e2 >>=
    int_of_numVal >>= fun n2 ->
    return @@ NumVal (n1-n2)
  | Mul(e1,e2) ->
    eval_expr e1 >>=
    int_of_numVal >>= fun n1 ->
    eval_expr e2 >>=
    int_of_numVal >>= fun n2 ->
    return @@ NumVal (n1*n2)
  | Div(e1,e2) ->
    eval_expr e1 >>=
    int_of_numVal >>= fun n1 ->
    eval_expr e2 >>=
    int_of_numVal >>= fun n2 ->
    if n2==0
    then error "Division by zero"
    else return @@ NumVal (n1/n2)
  | Let(v,def,body) ->
    eval_expr def >>= fun ev ->
    let l = Store.new_ref g_store ev
    in extend_env v (RefVal l) >>+
    eval_expr body
  | ITE(e1,e2,e3) ->
    eval_expr e1 >>=
    bool_of_boolVal >>= fun b ->
    if b
    then eval_expr e2
    else eval_expr e3
  | IsZero(e) ->
    eval_expr e >>=
    int_of_numVal >>= fun n ->
    return @@ BoolVal (n = 0)
  | Pair(e1,e2) ->
    eval_expr e1 >>= fun ev1 ->
    eval_expr e2 >>= fun ev2 ->
    return @@ PairVal(ev1,ev2)
  | Fst(e) ->
    eval_expr e >>=
    pair_of_pairVal >>= fun p ->
    return @@ fst p
  | Snd(e) ->
    eval_expr e >>=
    pair_of_pairVal >>= fun p ->
    return @@ snd p
  | Proc(id,e)  ->
    lookup_env >>= fun en ->
    return @@ ProcVal(id,e,en)
  | App(e1,e2)  ->
    eval_expr e1 >>= 
    clos_of_procVal >>= fun clos ->
    eval_expr e2 >>= 
    apply_clos clos
  | Letrec(id,par,e,target) ->
    let l = Store.new_ref g_store UnitVal in
    extend_env id (RefVal l) >>+
    (lookup_env >>= fun env ->
     Store.set_ref g_store l (ProcVal(par,e,env)) >>= fun _ ->
     eval_expr target
    )
  (* Mutable references operations *)
  | Set(id,e) ->
    eval_expr e >>= fun ev ->
    apply_env id >>=
    int_of_refVal >>= fun l ->
    Store.set_ref g_store l ev >>= fun _ ->
    return UnitVal
  | BeginEnd([]) ->
    return UnitVal
  | BeginEnd(es) -> 
    sequence (List.map eval_expr es) >>= fun vs ->
    return (List.hd (List.rev vs))
  (* Record operations *)
  | Record(fs) ->
    let (ids,es) = List.split fs
    in sequence (List.map eval_expr es) >>= fun evs ->
    return @@ RecordVal (List.combine ids evs)
  | Proj(e,id) ->
    eval_expr e >>=
    fields_of_recordVal >>= fun fs ->
    (match List.assoc_opt id fs with
    | None -> error "Proj: field not found"
    | Some ev -> return ev)
  (* SOOL operations *)
  | NewObject(c_name,es) ->
    sequence(List.map eval_expr es) >>= fun evs ->
    lookup_class c_name ! g_class_env >>= fun (super, fields, methods) ->
    new_env fields >>= fun env ->
    (match List.assoc_opt "initialize" methods with
    | None -> return @@ (ObjectVal(c_name,env))
    | Some m -> apply_method "initialize" (ObjectVal(c_name,env)) evs m >>= fun x ->
                  return @@ (ObjectVal(c_name,env)))
  | Send(e,m_name,args) ->
    eval_expr e >>= fun self ->
    (match self with
    | ObjectVal(c_name, _) -> sequence(List.map eval_expr args) >>= fun evs ->
                                (match lookup_method c_name m_name ! g_class_env with
                                | None -> error "Method not found"
                                | Some m -> apply_method m_name self evs m )
    | _ -> error "Not an Object")
  | Self ->
    eval_expr (Var "_self")
  | Super(m_name,args) ->
    sequence(List.map eval_expr args) >>= fun evs ->
    eval_expr (Var "_super") >>= string_of_stringVal >>= fun c_name ->
    eval_expr (Var "_self") >>= fun self ->
    (match lookup_method c_name m_name ! g_class_env with
    | None -> error "Method not found"
    | Some m -> apply_method m_name self evs m)
  (* List operations* *)
  | List(es) ->
    sequence (List.map eval_expr es) >>= fun args ->
    return @@ ListVal args
  | Cons(e1,e2) ->
    eval_expr e1 >>= fun ev ->
    eval_expr e2 >>=
    list_of_listVal >>= fun l ->
    return @@ ListVal (ev::l)
  | Hd(e) ->
    eval_expr e >>=
    list_of_listVal >>= fun l ->
    return @@ List.hd l
  | Tl(e) ->
    eval_expr e >>=
    list_of_listVal >>= fun l ->
    return @@ ListVal (List.tl l)
  | IsEmpty(e) ->
    eval_expr e >>=
    list_of_listVal >>= fun l ->
    return @@ BoolVal (l=[])
  (* Debug *)
  | Debug(_e) ->
    string_of_env >>= fun str_env ->
    let str_store = Store.string_of_store string_of_expval g_store
    in (print_endline (str_env^"\n"^str_store);
    error "Reached breakpoint")
  | _ -> failwith ("eval_expr: Not implemented: "^string_of_expr e)
and
  eval_prog : prog -> exp_val ea_result =
  fun (AProg(cs, e)) ->
  initialize_class_env cs;   (* Step 1 *) 
  eval_expr e                (* Step 2 *)


(* Parse a string into an ast *)

let parse s =
  let lexbuf = Lexing.from_string s in
  let ast = Parser.prog Lexer.read lexbuf in
  ast



let lexer s =
  let lexbuf = Lexing.from_string s
  in Lexer.read lexbuf


(* Interpret an expression *)
let interp (s:string) : exp_val result =
  let c = s |> parse |> eval_prog
  in run c

let read_file (filename:string) : string = 
  let lines = ref [] in
  let chan = open_in filename in
  try
    while true do
      lines := input_line chan :: !lines
    done;
    "" (* never reaches this line *)
  with End_of_file ->
    close_in chan;
    String.concat "" (List.rev !lines)

(* Parse an expression read from a file with optional extension .sool *)
let parsef (s:string) : prog = 
  let s = String.trim s      (* remove leading and trailing spaces *)
  in let file_name =    (* allow rec to be optional *)
       match String.index_opt s '.' with None -> s^".sool" | _ -> s
  in
  parse @@ read_file file_name


(* Interpret an expression read from a file with optional extension .sool *)
let interpf (s:string) : exp_val result = 
  let s = String.trim s      (* remove leading and trailing spaces *)
  in let file_name =    (* allow rec to be optional *)
       match String.index_opt s '.' with None -> s^".sool" | _ -> s
  in
  interp @@ read_file file_name

let interpp () : exp_val result = 
  interpf "ex1"



theory Ports_Normalize
imports Protocols_Normalize
begin


(*TODO: move to generic place and use? ? ? *)
datatype 'a match_compress = CannotMatch | MatchesAll | MatchExpr 'a



(*TODO: move*)
section\<open>L4 Ports Parser Helper\<close>

(********************************** parser helper *******************************************)

context
begin

  text\<open>Replace all matches on ports with the unspecified @{term 0} protocol with the given @{typ primitive_protocol}.\<close>
  private definition fill_l4_protocol_raw
    :: "primitive_protocol \<Rightarrow> 'i::len common_primitive negation_type list \<Rightarrow> 'i common_primitive negation_type list"
  where
    "fill_l4_protocol_raw proto \<equiv> NegPos_map
      (\<lambda> m. case m of Src_Ports (L4Ports x pts) \<Rightarrow> if x \<noteq> 0 then undefined else Src_Ports (L4Ports proto pts)
                   |  Dst_Ports (L4Ports x pts) \<Rightarrow> if x \<noteq> 0 then undefined else Dst_Ports (L4Ports proto pts)
                   |  Prot _ \<Rightarrow> undefined (*there should be no more match on the protocol if it was parsed from an iptables-save line*)
                   | m \<Rightarrow> m
      )"

  lemma "fill_l4_protocol_raw TCP [Neg (Dst (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8)), Pos (Src_Ports (L4Ports 0 [(22,22)]))] =
          [Neg (Dst (IpAddrNetmask 0x7F000000 8)), Pos (Src_Ports (L4Ports 6 [(0x16, 0x16)]))]" by eval


  fun fill_l4_protocol
    :: "'i::len common_primitive negation_type list \<Rightarrow> 'i::len common_primitive negation_type list"
  where
    "fill_l4_protocol [] = []" |
    "fill_l4_protocol (Pos (Prot (Proto proto)) # ms) = Pos (Prot (Proto proto)) # fill_l4_protocol_raw proto ms" |
    "fill_l4_protocol (Pos (Src_Ports _) # _) = undefined" | (*need to find proto first*)
    "fill_l4_protocol (Pos (Dst_Ports _) # _) = undefined" |
    "fill_l4_protocol (m # ms) = m # fill_l4_protocol ms"


  lemma "fill_l4_protocol [ Neg (Dst (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8))
                                , Neg (Prot (Proto UDP))
                                , Pos (Src (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8))
                                , Pos (Prot (Proto TCP))
                                , Pos (Extra ''foo'')
                                , Pos (Src_Ports (L4Ports 0 [(22,22)]))
                                , Neg (Extra ''Bar'')] =
  [ Neg (Dst (IpAddrNetmask 0x7F000000 8))
  , Neg (Prot (Proto UDP))
  , Pos (Src (IpAddrNetmask 0x7F000000 8))
  , Pos (Prot (Proto TCP))
  , Pos (Extra ''foo'')
  , Pos (Src_Ports (L4Ports TCP [(0x16, 0x16)]))
  , Neg (Extra ''Bar'')]" by eval

end

(********************************** parser helper *******************************************)




section\<open>Combine Match Expressions\<close>
(*TODO: move oder ich hab das schon irgendwo*)
(*TODO: this must be somewhere, deduplicate! look for fold and MatchAnd*)

fun andfold_MatchExp :: "'a match_expr list \<Rightarrow> 'a match_expr" where
  "andfold_MatchExp [] = MatchAny" |
  "andfold_MatchExp [e] = e" |
  "andfold_MatchExp (e#es) = MatchAnd e (andfold_MatchExp es)"

(*TODO: this must be somewhere, deduplicate! look for fold and MatchAnd*)
lemma andfold_MatchExp_alist_and: "alist_and (map Pos ls) = andfold_MatchExp (map Match ls)"
  apply(induction ls)
   apply(simp)+
  oops (*TODO: tune alist_and!*)

lemma andfold_MatchExp_matches:
  "matches (\<beta>, \<alpha>) (andfold_MatchExp ms) a p \<longleftrightarrow> (\<forall>m \<in> set ms. matches (\<beta>, \<alpha>) m a p)"
  apply(induction ms rule: andfold_MatchExp.induct)
    apply(simp add: bunch_of_lemmata_about_matches)+
  done

lemma andfold_MatchExp_not_disc_negated_mapMatch:
  "\<not> has_disc_negated disc False (andfold_MatchExp (map (Match \<circ> C) ls))"
  apply(induction ls)
   apply(simp; fail)
  apply(simp)
   apply(rename_tac ls, case_tac ls)
  by(simp)+


lemma andfold_MatchExp_not_disc_negatedI:
  "\<forall>m \<in> set ms. \<not> has_disc_negated disc False m \<Longrightarrow> \<not> has_disc_negated disc False (andfold_MatchExp ms)"
  apply(induction ms rule: andfold_MatchExp.induct)
    apply(simp)+
  done





section\<open>Normalizing L4 Ports\<close>
subsection\<open>Defining Normalized Ports\<close>
  
  fun normalized_src_ports :: "'i::len common_primitive match_expr \<Rightarrow> bool" where
    "normalized_src_ports MatchAny = True" |
    "normalized_src_ports (Match (Src_Ports (L4Ports _ []))) = True" |
    "normalized_src_ports (Match (Src_Ports (L4Ports _ [_]))) = True" |
    "normalized_src_ports (Match (Src_Ports _)) = False" |
    "normalized_src_ports (Match _) = True" |
    "normalized_src_ports (MatchNot (Match (Src_Ports _))) = False" |
    "normalized_src_ports (MatchNot (Match _)) = True" |
    "normalized_src_ports (MatchAnd m1 m2) = (normalized_src_ports m1 \<and> normalized_src_ports m2)" |
    "normalized_src_ports (MatchNot (MatchAnd _ _)) = False" |
    "normalized_src_ports (MatchNot (MatchNot _)) = False" |
    "normalized_src_ports (MatchNot MatchAny) = True"
  
  fun normalized_dst_ports :: "'i::len common_primitive match_expr \<Rightarrow> bool" where
    "normalized_dst_ports MatchAny = True" |
    "normalized_dst_ports (Match (Dst_Ports (L4Ports _ []))) = True" |
    "normalized_dst_ports (Match (Dst_Ports (L4Ports _ [_]))) = True" |
    "normalized_dst_ports (Match (Dst_Ports _)) = False" |
    "normalized_dst_ports (Match _) = True" |
    "normalized_dst_ports (MatchNot (Match (Dst_Ports _))) = False" |
    "normalized_dst_ports (MatchNot (Match _)) = True" |
    "normalized_dst_ports (MatchAnd m1 m2) = (normalized_dst_ports m1 \<and> normalized_dst_ports m2)" |
    "normalized_dst_ports (MatchNot (MatchAnd _ _)) = False" |
    "normalized_dst_ports (MatchNot (MatchNot _)) = False" |
    "normalized_dst_ports (MatchNot MatchAny) = True" 

  lemma normalized_src_ports_def2: "normalized_src_ports ms = normalized_n_primitive (is_Src_Ports, src_ports_sel) (\<lambda>ps. case ps of L4Ports _ pts \<Rightarrow> length pts \<le> 1) ms"
    by(induction ms rule: normalized_src_ports.induct, simp_all)
  lemma normalized_dst_ports_def2: "normalized_dst_ports ms = normalized_n_primitive (is_Dst_Ports, dst_ports_sel) (\<lambda>ps. case ps of L4Ports _ pts \<Rightarrow> length pts \<le> 1) ms"
    by(induction ms rule: normalized_dst_ports.induct, simp_all)




text\<open>Idea: first, remove all negated matches, then @{const normalize_match},
  then only work with @{const primitive_extractor} on @{const Pos} ones.
  They only need an intersect and split later on. 

  This is not very efficient because normalizing nnf will blow up a lot.
  but we can tune performance later on go for correctness first!
  Anything with @{const MatchOr} and @{const normalize_match} later is a bit inefficient.
\<close>




subsection\<open>Compressing Positive Matches on Ports into a Single Match\<close>
(*compressing positive matches on ports into a single match*)

  fun l4_ports_compress :: "ipt_l4_ports list \<Rightarrow> ipt_l4_ports match_compress" where
    "l4_ports_compress [] = MatchesAll" | 
    "l4_ports_compress [ps] = MatchExpr ps" |
    "l4_ports_compress (L4Ports proto1 ps1 # L4Ports proto2 ps2 # pss) =
      (if
          proto1 \<noteq> proto2
       then
         CannotMatch
       else
         l4_ports_compress (L4Ports proto1 (wi2l (wordinterval_intersection (l2wi ps1) (l2wi ps2))) # pss)
      )"
  
  (*only for src*)
  lemma raw_ports_compress_src_CannotMatch:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  and c: "l4_ports_compress pss = CannotMatch"
  shows "\<not> matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Src_Ports) pss)) a p"
  using c apply(induction pss rule: l4_ports_compress.induct)
    apply(simp; fail)
   apply(simp; fail)
  apply(simp add: primitive_matcher_generic.Ports_single[OF generic] bunch_of_lemmata_about_matches split: split_if_asm)
   apply meson
  by(simp add: l2wi_wi2l ports_to_set_wordinterval)

  lemma raw_ports_compress_dst_CannotMatch:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  and c: "l4_ports_compress pss = CannotMatch"
  shows "\<not> matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Dst_Ports) pss)) a p"
  using c apply(induction pss rule: l4_ports_compress.induct)
    apply(simp; fail)
   apply(simp; fail)
  apply(simp add: primitive_matcher_generic.Ports_single[OF generic] bunch_of_lemmata_about_matches split: split_if_asm)
   apply meson
  by(simp add: l2wi_wi2l ports_to_set_wordinterval)

  lemma l4_ports_compress_length_Matchall: "length pss > 0 \<Longrightarrow> l4_ports_compress pss \<noteq> MatchesAll"
    by(induction pss rule: l4_ports_compress.induct) simp+

  lemma raw_ports_compress_MatchesAll:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  and c: "l4_ports_compress pss = MatchesAll"
  shows "matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Src_Ports) pss)) a p"
  and "matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Dst_Ports) pss)) a p"
  using c apply(induction pss rule: l4_ports_compress.induct)
  by(simp add: l4_ports_compress_length_Matchall bunch_of_lemmata_about_matches split: split_if_asm)+


  lemma raw_ports_compress_src_MatchExpr:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  and c: "l4_ports_compress pss = MatchExpr m"
  shows "matches (\<beta>, \<alpha>) (Match (Src_Ports m)) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Src_Ports) pss)) a p"
  using c apply(induction pss arbitrary: m rule: l4_ports_compress.induct)
    apply(simp add: bunch_of_lemmata_about_matches; fail)
   apply(simp add: bunch_of_lemmata_about_matches; fail)
  apply(case_tac m)
  apply(simp add: bunch_of_lemmata_about_matches split: split_if_asm)
  apply(simp add: primitive_matcher_generic.Ports_single[OF generic])
  apply(simp add: l2wi_wi2l ports_to_set_wordinterval)
  by fastforce
  

  lemma raw_ports_compress_dst_MatchExpr:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  and c: "l4_ports_compress pss = MatchExpr m"
  shows "matches (\<beta>, \<alpha>) (Match (Dst_Ports m)) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) (alist_and (map (Pos \<circ> Dst_Ports) pss)) a p"
  using c apply(induction pss arbitrary: m rule: l4_ports_compress.induct)
    apply(simp add: bunch_of_lemmata_about_matches; fail)
   apply(simp add: bunch_of_lemmata_about_matches; fail)
  apply(case_tac m)
  apply(simp add: bunch_of_lemmata_about_matches split: split_if_asm)
  apply(simp add: primitive_matcher_generic.Ports_single[OF generic])
  apply(simp add: l2wi_wi2l ports_to_set_wordinterval)
  by fastforce




subsection\<open>Rewriting Negated Matches on Ports\<close>

  fun l4_ports_negate_one
    :: "(ipt_l4_ports \<Rightarrow> 'i common_primitive) \<Rightarrow> ipt_l4_ports \<Rightarrow> ('i::len common_primitive) match_expr"
  where
    "l4_ports_negate_one C (L4Ports proto pts) = MatchOr
           (MatchNot (Match (Prot (Proto proto))))
            (Match (C (L4Ports proto (raw_ports_invert pts))))"

  lemma l4_ports_negate_one:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "matches (\<beta>, \<alpha>) (l4_ports_negate_one Src_Ports ports) a p \<longleftrightarrow>
          matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports ports))) a p"
  and "matches (\<beta>, \<alpha>) (l4_ports_negate_one Dst_Ports ports) a p \<longleftrightarrow>
          matches (\<beta>, \<alpha>) (MatchNot (Match (Dst_Ports ports))) a p"
    apply(case_tac [!] ports)
    by(auto simp add: primitive_matcher_generic.Ports_single_not[OF generic]
                    MatchOr bunch_of_lemmata_about_matches
                    primitive_matcher_generic.Prot_single_not[OF generic]
                    primitive_matcher_generic.Ports_single[OF generic]
                    raw_ports_invert)

  lemma l4_ports_negate_one_not_has_disc_negated:
    "\<not> has_disc_negated is_Src_Ports False (l4_ports_negate_one Src_Ports ports)"
    "\<not> has_disc_negated is_Dst_Ports False (l4_ports_negate_one Dst_Ports ports)"
    apply(case_tac [!] ports, rename_tac proto pts)
     by(simp add: MatchOr_def)+
    
  text\<open>beware, the result is not nnf normalized!\<close>
  lemma "\<not> normalized_nnf_match (l4_ports_negate_one C ports)"
    by(cases ports) (simp add: MatchOr_def)
  
  declare l4_ports_negate_one.simps[simp del]

    
  lemma "((normalize_match (l4_ports_negate_one Src_Ports (L4Ports TCP [(22,22),(80,90)]))):: 32 common_primitive match_expr list)
    =
    [ MatchNot (Match (Prot (Proto TCP)))
    , Match (Src_Ports (L4Ports 6 [(0, 21), (23, 79), (91, 0xFFFF)]))]" by eval


  (*TODO move as internal to next proof*)
  lemma spts: 
    "(\<forall>m\<in>set (getNeg spts). matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports m))) a p) \<and> (\<forall>m\<in>set (getPos spts). matches (\<beta>, \<alpha>) (Match (Src_Ports m)) a p)
      \<longleftrightarrow>
      matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports spts)) a p"
    apply(induction spts rule: alist_and.induct)
      apply(simp add: bunch_of_lemmata_about_matches; fail)
     by(auto simp add: bunch_of_lemmata_about_matches)


  definition rewrite_negated_primitives
    :: "(('a \<Rightarrow> bool) \<times> ('a \<Rightarrow> 'b)) \<Rightarrow> ('b \<Rightarrow> 'a) \<Rightarrow> (*dsic_sel C*)
        (('b \<Rightarrow> 'a) \<Rightarrow> 'b \<Rightarrow> 'a match_expr) \<Rightarrow> (*negate_one function*)
        'a match_expr \<Rightarrow> 'a match_expr" where
    "rewrite_negated_primitives disc_sel C negate m \<equiv>
        let (spts, rst) = primitive_extractor disc_sel m
        in MatchAnd
            (andfold_MatchExp (map (negate C) (getNeg spts)))
            (MatchAnd
              (andfold_MatchExp (map (Match \<circ> C) (getPos spts))) (*TODO: compress all the positive ports into one?*)
            rst)"


  (*TODO: write primitive_extractor with "let" instead of "case" more often?*)
  (*TODO: generalize for src/dst ports!!!*)
  definition rewrite_negated_src_ports
    :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr" where
    "rewrite_negated_src_ports m \<equiv>
        let (spts, rst) = primitive_extractor (is_Src_Ports, src_ports_sel) m
        in MatchAnd
            (andfold_MatchExp (map (l4_ports_negate_one Src_Ports) (getNeg spts)))
            (MatchAnd
              (andfold_MatchExp (map (Match \<circ> Src_Ports) (getPos spts))) (*TODO: compress all the positive ports into one?*)
            rst)"

  lemma "rewrite_negated_src_ports m =
          rewrite_negated_primitives (is_Src_Ports, src_ports_sel) Src_Ports l4_ports_negate_one m"
    by(simp add: rewrite_negated_primitives_def rewrite_negated_src_ports_def)
  
  lemma rewrite_negated_src_ports:
  assumes generic: "primitive_matcher_generic \<beta>"  and n: "normalized_nnf_match m"
  shows "matches (\<beta>, \<alpha>) (rewrite_negated_src_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
  apply(simp add: rewrite_negated_src_ports_def)
  apply(case_tac "primitive_extractor (is_Src_Ports, src_ports_sel) m", rename_tac spts rst)
  apply(simp)
  apply(simp add: bunch_of_lemmata_about_matches)
  apply(subst primitive_extractor_correct(1)[OF n wf_disc_sel_common_primitive(1), where \<gamma>="(\<beta>, \<alpha>)" and a=a and p=p, symmetric])
   apply(simp; fail)
  apply(simp add: andfold_MatchExp_matches)
  apply(simp add: l4_ports_negate_one[OF generic])
  apply(subgoal_tac "matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports spts)) a p \<longleftrightarrow>
          (\<forall>m\<in>set (getNeg spts). matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports m))) a p) \<and> (\<forall>m\<in>set (getPos spts). matches (\<beta>, \<alpha>) (Match (Src_Ports m)) a p)")
   apply(simp; fail)
  apply(simp add: spts)
  done

  lemma rewrite_negated_src_ports_not_has_disc_negated:
  assumes n: "normalized_nnf_match m"
  shows  "\<not> has_disc_negated is_Src_Ports False (rewrite_negated_src_ports m)"
    apply(simp add: rewrite_negated_src_ports_def)
    apply(case_tac "primitive_extractor (is_Src_Ports, src_ports_sel) m", rename_tac spts rst)
    apply(simp)
    apply(frule primitive_extractor_correct(3)[OF n wf_disc_sel_common_primitive(1)])
    apply(intro conjI)
      apply(rule andfold_MatchExp_not_disc_negatedI)
      apply(simp add: l4_ports_negate_one_not_has_disc_negated; fail)
     using andfold_MatchExp_not_disc_negated_mapMatch apply blast
    using has_disc_negated_has_disc by blast
    

  lemma "\<not> has_disc_negated disc t m \<Longrightarrow> \<forall>m' \<in> set (normalize_match m). \<not> has_disc_negated disc t m'"
    by(fact i_m_giving_this_a_funny_name_so_i_can_thank_my_future_me_when_sledgehammer_will_find_this_one_day)

  corollary normalize_rewrite_negated_src_ports_not_has_disc_negated:
  assumes n: "normalized_nnf_match m"
  shows "\<forall>m' \<in> set (normalize_match (rewrite_negated_src_ports m)). \<not> has_disc_negated is_Src_Ports False m'"
    apply(rule i_m_giving_this_a_funny_name_so_i_can_thank_my_future_me_when_sledgehammer_will_find_this_one_day)
    apply(rule rewrite_negated_src_ports_not_has_disc_negated)
    using n by simp



subsection\<open>Normalizing Positive Matches on Ports\<close>
(*now normalizing the match expression which does not have negated ports*)

(*creates a disjunction where all interval lists only have one element*)
  fun singletonize_L4Ports :: "ipt_l4_ports \<Rightarrow> ipt_l4_ports list" where
    "singletonize_L4Ports (L4Ports proto pts) = map (\<lambda>p. L4Ports proto [p]) pts"

  lemma singletonize_L4Ports_src: assumes generic: "primitive_matcher_generic \<beta>"
   shows "match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) (singletonize_L4Ports pts)) a p \<longleftrightarrow> 
    matches (\<beta>, \<alpha>) (Match (Src_Ports pts)) a p"
    apply(cases pts)
    apply(simp add: match_list_matches primitive_matcher_generic.Ports_single[OF generic])
    apply(simp add: ports_to_set)
    by auto

  lemma singletonize_L4Ports_dst: assumes generic: "primitive_matcher_generic \<beta>"
   shows "match_list (\<beta>, \<alpha>) (map (Match \<circ> Dst_Ports) (singletonize_L4Ports pts)) a p \<longleftrightarrow> 
    matches (\<beta>, \<alpha>) (Match (Dst_Ports pts)) a p"
    apply(cases pts)
    apply(simp add: match_list_matches primitive_matcher_generic.Ports_single[OF generic])
    apply(simp add: ports_to_set)
    by auto

  declare singletonize_L4Ports.simps[simp del]



  text\<open>Normalizing match expressions such that at most one port will exist in it. Returns a list of match expressions (splits one firewall rule into several rules).\<close>
  definition normalize_positive_ports_step :: "(('i::len common_primitive \<Rightarrow> bool) \<times> ('i common_primitive \<Rightarrow> ipt_l4_ports)) \<Rightarrow> 
                               (ipt_l4_ports \<Rightarrow> 'i common_primitive) \<Rightarrow>
                               'i common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where 
    "normalize_positive_ports_step (disc_sel) C m \<equiv>
        let (spts, rst) = primitive_extractor (disc_sel) m in
        case (getPos spts, getNeg spts)
          of (pspts, []) \<Rightarrow> (case l4_ports_compress pspts of CannotMatch \<Rightarrow> []
                                                          |  MatchesAll \<Rightarrow> [rst]
                                                          |  MatchExpr m \<Rightarrow> map (\<lambda>spt. (MatchAnd (Match (C spt)) rst)) (singletonize_L4Ports m)
                            )
          |  (_, _) \<Rightarrow> undefined"

  (*TODO: add that we need to remove all negated ports first and the normalize again for the complete picture*)

  definition normalize_positive_src_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_positive_src_ports = normalize_positive_ports_step (is_Src_Ports, src_ports_sel) Src_Ports"  
  definition normalize_positive_dst_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_positive_dst_ports = normalize_positive_ports_step (is_Dst_Ports, dst_ports_sel) Dst_Ports"

  (*TODO: into next lemmas?*)
  lemma noNeg_mapNegPos_helper: "getNeg ls = [] \<Longrightarrow>
           map (Pos \<circ> C) (getPos ls) = NegPos_map C ls"
    by(induction ls rule: getPos.induct) simp+

  lemma normalize_positive_src_ports:
    assumes generic: "primitive_matcher_generic \<beta>"
    and n: "normalized_nnf_match m"
    and noneg: "\<not> has_disc_negated is_Src_Ports False m"
    shows
        "match_list (\<beta>, \<alpha>) (normalize_positive_src_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
    apply(simp add: normalize_positive_src_ports_def normalize_positive_ports_step_def)
    apply(case_tac "primitive_extractor (is_Src_Ports, src_ports_sel) m", rename_tac spts rst)
    apply(simp)
    apply(subgoal_tac "getNeg spts = []") (*needs assumption for this step *)
     prefer 2 subgoal
     apply(drule primitive_extractor_correct(8)[OF n wf_disc_sel_common_primitive(1)])
      using noneg by simp+
    apply(simp)
    apply(drule primitive_extractor_correct(1)[OF n wf_disc_sel_common_primitive(1), where \<gamma>="(\<beta>, \<alpha>)" and a=a and p=p])
    apply(case_tac "l4_ports_compress (getPos spts)")
       apply(simp)
       apply(drule raw_ports_compress_src_CannotMatch[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
       apply(simp add: noNeg_mapNegPos_helper; fail)
      apply(simp)
      apply(drule raw_ports_compress_MatchesAll[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
      apply(simp add: noNeg_mapNegPos_helper; fail)
     apply(simp add: bunch_of_lemmata_about_matches)
     apply(drule raw_ports_compress_src_MatchExpr[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
     apply(insert singletonize_L4Ports_src[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
     apply(simp add: match_list_matches)
     apply(simp add: bunch_of_lemmata_about_matches)
     apply(simp add: noNeg_mapNegPos_helper; fail)
    done

  (*copy & paste, TODO generalize*)
  lemma normalize_positive_dst_ports:
    assumes generic: "primitive_matcher_generic \<beta>"
    and n: "normalized_nnf_match m"
    and noneg: "\<not> has_disc_negated is_Dst_Ports False m"
    shows "match_list (\<beta>, \<alpha>) (normalize_positive_dst_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
    apply(simp add: normalize_positive_dst_ports_def normalize_positive_ports_step_def)
    apply(case_tac "primitive_extractor (is_Dst_Ports, dst_ports_sel) m", rename_tac spts rst)
    apply(simp)
    apply(subgoal_tac "getNeg spts = []") (*needs assumption for this step *)
     prefer 2 subgoal
     apply(drule primitive_extractor_correct(8)[OF n wf_disc_sel_common_primitive(2)])
      using noneg by simp+
    apply(simp)
    apply(drule primitive_extractor_correct(1)[OF n wf_disc_sel_common_primitive(2), where \<gamma>="(\<beta>, \<alpha>)" and a=a and p=p])
    apply(case_tac "l4_ports_compress (getPos spts)")
       apply(simp)
       apply(drule raw_ports_compress_dst_CannotMatch[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
       apply(simp add: noNeg_mapNegPos_helper; fail)
      apply(simp)
      apply(drule raw_ports_compress_MatchesAll(2)[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
      apply(simp add: noNeg_mapNegPos_helper; fail)
     apply(simp add: bunch_of_lemmata_about_matches)
     apply(drule raw_ports_compress_dst_MatchExpr[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
     apply(insert singletonize_L4Ports_dst[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
     apply(simp add: match_list_matches)
     apply(simp add: bunch_of_lemmata_about_matches)
     apply(simp add: noNeg_mapNegPos_helper; fail)
    done    


  lemma normalize_positive_src_ports_nnf:
    assumes n: "normalized_nnf_match m"
    and noneg: "\<not> has_disc_negated is_Src_Ports False m"
    shows "m' \<in> set (normalize_positive_src_ports m) \<Longrightarrow> normalized_nnf_match m'"
    apply(simp add: normalize_positive_src_ports_def normalize_positive_ports_step_def)
    apply(elim exE conjE, rename_tac rst spts)
    apply(drule sym) (*switch primitive_extrartor = *)
    apply(frule primitive_extractor_correct(2)[OF n wf_disc_sel_common_primitive(1)])
    apply(subgoal_tac "getNeg spts = []") (*duplication above*)
     prefer 2 subgoal
     apply(drule primitive_extractor_correct(8)[OF n wf_disc_sel_common_primitive(1)])
      using noneg by simp+
    apply(simp split: match_compress.split_asm)
    by fastforce


  (*copy & paste, TODO generalize*)
  lemma normalize_positive_dst_ports_nnf:
    assumes n: "normalized_nnf_match m"
    and noneg: "\<not> has_disc_negated is_Dst_Ports False m"
    shows "m' \<in> set (normalize_positive_dst_ports m) \<Longrightarrow> normalized_nnf_match m'"
    apply(simp add: normalize_positive_dst_ports_def normalize_positive_ports_step_def)
    apply(elim exE conjE, rename_tac rst spts)
    apply(drule sym) (*switch primitive_extrartor = *)
    apply(frule primitive_extractor_correct(2)[OF n wf_disc_sel_common_primitive(2)])
    apply(subgoal_tac "getNeg spts = []") (*duplication above*)
     prefer 2 subgoal
     apply(drule primitive_extractor_correct(8)[OF n wf_disc_sel_common_primitive(2)])
      using noneg by simp+
    apply(simp split: match_compress.split_asm)
    by fastforce


subsection\<open>Complete Normalization\<close>
    
  definition normalize_src_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_src_ports m = concat (map normalize_positive_src_ports (normalize_match (rewrite_negated_src_ports m)))"  

  (*
  definition normalize_dst_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_dst_ports m = concat (map normalize_positive_dst_ports (normalize_match (rewrite_negated_dst_ports m)))" *)

  lemma in_normalized_matches: "ls \<in> set (normalize_match m) \<and> matches \<gamma> ls a p \<Longrightarrow> matches \<gamma> m a p"
    by (meson match_list_matches matches_to_match_list_normalize)


  lemma normalize_src_ports:
    assumes generic: "primitive_matcher_generic \<beta>"
    and n: "normalized_nnf_match m"
    shows
        "match_list (\<beta>, \<alpha>) (normalize_src_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
     apply(simp add: normalize_src_ports_def)
     apply(rule)
      subgoal
      apply(simp add: match_list_concat)
      apply(clarify, rename_tac ls)
      apply(subst(asm) normalize_positive_src_ports[OF generic])
        using normalized_nnf_match_normalize_match apply blast
       using normalize_rewrite_negated_src_ports_not_has_disc_negated[OF n] apply blast
      apply(subgoal_tac "normalized_nnf_match ls")
       prefer 2
       using normalized_nnf_match_normalize_match apply blast
      apply(subgoal_tac "matches (\<beta>, \<alpha>) (rewrite_negated_src_ports m) a p")
       thm rewrite_negated_src_ports[OF generic n, where \<alpha>=\<alpha> and a=a and p=p]
       using rewrite_negated_src_ports[OF generic n, where \<alpha>=\<alpha> and a=a and p=p] apply blast
      thm in_normalized_matches[where \<gamma>="(\<beta>,\<alpha>)" and a=a and p=p]
      using in_normalized_matches[where \<gamma>="(\<beta>,\<alpha>)" and a=a and p=p] apply blast
      done
     
     apply(subst(asm) rewrite_negated_src_ports[OF generic n, where \<alpha>=\<alpha> and a=a and p=p, symmetric])
     apply(subst(asm) matches_to_match_list_normalize)
     apply(subst(asm) match_list_matches)
     apply(elim bexE, rename_tac ls)
     apply(subgoal_tac "normalized_nnf_match ls")
      prefer 2
      using normalized_nnf_match_normalize_match apply blast
     apply(simp add: match_list_concat)
     apply(rule_tac x=ls in bexI)
      prefer 2 apply(simp; fail)
     apply(subst normalize_positive_src_ports[OF generic])
       apply(simp_all)
     using normalize_rewrite_negated_src_ports_not_has_disc_negated[OF n] apply blast
     done



(*TODO: die ganzen matchAnys gehoeren mal ordentlich weg!*)
value[code] "normalize_src_ports
                (MatchAnd (Match (Dst (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8)))
                   (MatchAnd (Match (Prot (Proto TCP)))
                        (MatchNot (Match (Src_Ports (L4Ports UDP [(80,80)]))))
                 ))"


lemma"map opt_MatchAny_match_expr (normalize_src_ports
                (MatchAnd (Match (Dst (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8)))
                   (MatchAnd (Match (Prot (Proto TCP)))
                        (MatchNot (Match (Src_Ports (L4Ports UDP [(80,80)]))))
                 ))) =
 [MatchAnd (MatchNot (Match (Prot (Proto UDP)))) (MatchAnd (Match (Dst (IpAddrNetmask 0x7F000000 8))) (Match (Prot (Proto TCP)))),
  MatchAnd (Match (Src_Ports (L4Ports UDP [(0, 79)]))) (MatchAnd (Match (Dst (IpAddrNetmask 0x7F000000 8))) (Match (Prot (Proto TCP)))),
  MatchAnd (Match (Src_Ports (L4Ports UDP [(81, 0xFFFF)]))) (MatchAnd (Match (Dst (IpAddrNetmask 0x7F000000 8))) (Match (Prot (Proto TCP))))]" by eval

lemma "map opt_MatchAny_match_expr (normalize_src_ports
                (MatchAnd (Match (Dst (IpAddrNetmask (ipv4addr_of_dotdecimal (127, 0, 0, 0)) 8)))
                   (MatchAnd (Match (Prot (Proto ICMP)))
                     (MatchAnd (Match (Src_Ports (L4Ports TCP [(22,22)])))
                        (MatchNot (Match (Src_Ports (L4Ports UDP [(80,80)]))))
                 ))))
 =
[MatchAnd (Match (Src_Ports (L4Ports TCP [(22, 22)])))
   (MatchAnd (MatchNot (Match (Prot (Proto UDP)))) (MatchAnd (Match (Dst (IpAddrNetmask 0x7F000000 8))) (MatchAnd (Match (Prot (Proto ICMP))) MatchAny)))]" by eval

(****)




  lemma singletonize_L4Ports_normalized_src_ports:
    "m' \<in> (\<lambda>spt. Match (Src_Ports spt)) ` set (singletonize_L4Ports pt) \<Longrightarrow> normalized_src_ports m'"
    apply(case_tac pt)
    apply(simp add: singletonize_L4Ports.simps)
    apply(induction m' rule: normalized_src_ports.induct)
    by(auto)


  (*TODO: move?*)
  lemma normalized_n_primitive_MatchAnd_combine_map: "normalized_n_primitive disc_sel f rst \<Longrightarrow>
         \<forall>m' \<in> (\<lambda>spt. Match (C spt)) ` set pts. normalized_n_primitive disc_sel f m' \<Longrightarrow>
          m' \<in> (\<lambda>spt. MatchAnd (Match (C spt)) rst) ` set pts \<Longrightarrow> normalized_n_primitive disc_sel f m'"
    by(induction disc_sel f m' rule: normalized_n_primitive.induct)
       fastforce+
    
  lemma normalized_src_ports_singletonize_combine_rst: 
  "normalized_src_ports rst \<Longrightarrow> m' \<in> (\<lambda>spt. MatchAnd (Match (Src_Ports spt)) rst) ` set (singletonize_L4Ports pt) \<Longrightarrow> normalized_src_ports m'"
   unfolding normalized_src_ports_def2
   apply(rule normalized_n_primitive_MatchAnd_combine_map)
     apply(simp_all)
   using singletonize_L4Ports_normalized_src_ports[simplified normalized_src_ports_def2] by fastforce

  lemma normalize_positive_src_ports_normalized_n_primitive: 
    assumes n: "normalized_nnf_match m"
    and noneg: "\<not> has_disc_negated is_Src_Ports False m"
    shows "\<forall>m' \<in> set (normalize_positive_src_ports m). normalized_src_ports m'"
  unfolding normalize_positive_src_ports_def normalize_positive_ports_step_def
    apply(intro ballI, rename_tac m')
    apply(simp)
    apply(elim exE conjE, rename_tac rst spts)
    apply(drule sym) (*switch primitive_extrartor = *)
    apply(frule primitive_extractor_correct(2)[OF n wf_disc_sel_common_primitive(1)])
    apply(frule primitive_extractor_correct(3)[OF n wf_disc_sel_common_primitive(1)])
    thm primitive_extractor_correct[OF n wf_disc_sel_common_primitive(1)]
    apply(subgoal_tac "getNeg spts = []") (*duplication above*)
     prefer 2 subgoal
     apply(drule primitive_extractor_correct(8)[OF n wf_disc_sel_common_primitive(1)])
      using noneg by simp+
    apply(subgoal_tac "normalized_src_ports rst")
     prefer 2 subgoal
     unfolding normalized_src_ports_def2
     by(drule(2) normalized_n_primitive_if_no_primitive)
    apply(simp split: match_compress.split_asm)
    using normalized_src_ports_singletonize_combine_rst by blast
  

  lemma normalize_src_ports_normalized_n_primitive: "normalized_nnf_match m \<Longrightarrow> 
      \<forall>m' \<in> set (normalize_src_ports m). normalized_src_ports m'"
  unfolding normalize_src_ports_def
  apply(intro ballI, rename_tac m')
  apply(simp)
  apply(elim bexE, rename_tac a)
  apply(subgoal_tac "normalized_nnf_match a")
   prefer 2
   using normalized_nnf_match_normalize_match apply blast
  apply(subgoal_tac "\<not> has_disc_negated is_Src_Ports False a")
   prefer 2
   using normalize_rewrite_negated_src_ports_not_has_disc_negated apply blast
  apply(subgoal_tac "normalized_nnf_match m'")
   prefer 2
   using normalize_positive_src_ports_nnf apply blast
  using normalize_positive_src_ports_normalized_n_primitive by blast










(*    TODO: noralize Src_Ports Dst_Ports and Prot by removing impossible matches!    *)





lemma "False" oops





(*

(*
  (* [ [(1,2) \<or> (3,4)]  \<and>  [] ]*)
  text\<open>@{typ "raw_ports \<Rightarrow> raw_ports \<Rightarrow> raw_ports"}\<close>
  definition raw_ports_conjunct
    :: "('a::len word \<times> 'a::len word) list \<Rightarrow> ('a::len word \<times> 'a::len word) list \<Rightarrow> ('a::len word \<times> 'a::len word) list"
    where
    "raw_ports_conjunct ps1 ps2 = wi2l (wordinterval_intersection (l2wi ps1) (l2wi ps2))"
  
  lemma raw_ports_conjunct:
    "ports_to_set (raw_ports_conjunct ps1 ps2) = ports_to_set ps1 \<inter> ports_to_set ps2"
    apply(simp add: raw_ports_conjunct_def)
    by(simp add: ports_to_set_wordinterval l2wi_wi2l)
  
  fun l4_src_ports_conjunct
    :: "ipt_l4_ports \<Rightarrow> ipt_l4_ports \<Rightarrow> ipt_l4_ports option" where
    "l4_src_ports_conjunct (L4Ports proto1 ps1) (L4Ports proto2 ps2) = (
      if
        proto1 \<noteq> proto2
      then
        None
      else Some (L4Ports proto1 (raw_ports_conjunct ps1 ps2))
      (*raw_ports_conjunct ps1 ps2 can still return an empty,impossible i.e. [(0,-1)] range
        TODO: this could be further optimized here to return None more often*)
      )"


  lemma l4_src_ports_conjunct_Some:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "l4_src_ports_conjunct ps1 ps2 = Some ps' \<Longrightarrow> 
         matches (\<beta>, \<alpha>) (Match (Src_Ports ps')) a p =
          (matches (\<beta>, \<alpha>) (Match (Src_Ports ps1)) a p \<and> matches (\<beta>, \<alpha>) (Match (Src_Ports ps2)) a p)"
    apply(cases ps1, cases ps2, cases ps', rename_tac pr1 po1 pr2 po2 pr3 po3)
    apply(simp)
    apply(case_tac "pr1 \<noteq> pr2")
     apply(simp; fail)
    apply(simp)
    apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Ports_single[OF generic])
    using raw_ports_conjunct by auto
  
  lemma l4_src_ports_conjunct_None:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "l4_src_ports_conjunct ps1 ps2 = None \<Longrightarrow> 
         \<not> (matches (\<beta>, \<alpha>) (Match (Src_Ports ps1)) a p \<and> matches (\<beta>, \<alpha>) (Match (Src_Ports ps2)) a p)"
    apply(cases ps1, cases ps2)
     apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Ports_single[OF generic])
     apply fastforce
    done
  
  declare l4_src_ports_conjunct.simps[simp del]

  corollary l4_src_ports_conjunct:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "(matches (\<beta>, \<alpha>) (Match (Src_Ports ps1)) a p \<and> matches (\<beta>, \<alpha>) (Match (Src_Ports ps2)) a p)
        \<longleftrightarrow>
        (case l4_src_ports_conjunct ps1 ps2 of None \<Rightarrow> False | Some ps' \<Rightarrow> matches (\<beta>, \<alpha>) (Match (Src_Ports ps')) a p)"
    apply(cases "l4_src_ports_conjunct ps1 ps2")
     using l4_src_ports_conjunct_None[OF generic] l4_src_ports_conjunct_Some[OF generic]
     by simp+

 (*TODO: rename to L4 Ports Normalizes and move stuff to ports!*)





(*just another attempt, same stuff below*)
  text\<open>Negate the match on one @{const L4Ports}.\<close>

  (* Version 1: returns a list which corresponds to a disjunction. unhandy!

  (*Output: disjunction over the the things in the tuple!*)
  fun l4_src_ports_normalize_negate :: "ipt_l4_ports \<Rightarrow> (primitive_protocol \<times> ipt_l4_ports list)" where
    "l4_src_ports_normalize_negate (L4Ports proto pts) =
          (
            proto,
            (singletonize_L4Ports proto (raw_ports_invert pts))
          )"

  lemma l4_src_ports_normalize_negate:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
      and sports: "(protocol, ports) = (l4_src_ports_normalize_negate src_ports)"
  shows "match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) ports) a p \<or>
         matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto protocol)))) a p \<longleftrightarrow>
           matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports src_ports))) a p"
    (*apply(simp add: match_list_matches)*)
    apply(cases src_ports, rename_tac proto pts)
    apply(simp)
    apply(insert sports)
    apply(simp)
    apply(subst singletonize_L4Ports[OF generic])
    apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Prot_single_not[OF generic] primitive_matcher_generic.Ports_single[OF generic])
    apply(simp add: primitive_matcher_generic.Ports_single_not[OF generic])
    apply(simp add: raw_ports_invert)
    by blast
  
  lemma l4_src_ports_normalize_negate_cor:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
      and sports: "(protocol, ports) = (l4_src_ports_normalize_negate src_ports)"
  shows "match_list (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto protocol))) # map (Match \<circ> Src_Ports) ports) a p \<longleftrightarrow>
           matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports src_ports))) a p"
    apply(subst l4_src_ports_normalize_negate[OF generic sports, symmetric])
    by(simp)

  *)

  text\<open>Negate the match on one @{const L4Ports}.\<close>
  (*Output: disjunction over the the things in the tuple!*)
  fun l4_src_ports_negate :: "ipt_l4_ports \<Rightarrow> (primitive_protocol \<times> ipt_l4_ports)" where
    "l4_src_ports_negate (L4Ports proto pts) =
          (
            proto,
            (L4Ports proto (raw_ports_invert pts))
          )"

  lemma l4_src_ports_negate:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
      and sports: "(protocol, port) = (l4_src_ports_negate src_ports)"
  shows
    "matches (\<beta>, \<alpha>) (Match (Src_Ports port)) a p \<or> matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto protocol)))) a p
        \<longleftrightarrow>
     matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports src_ports))) a p"
    (*apply(simp add: match_list_matches)*)
    apply(cases src_ports, rename_tac proto pts)
    apply(simp)
    apply(insert sports)
    apply(simp)
    apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Prot_single_not[OF generic])
    apply(simp add: primitive_matcher_generic.Ports_single_not[OF generic])
    apply(simp add: primitive_matcher_generic.Ports_single[OF generic])
    apply(simp add: raw_ports_invert)
    by blast
  
  lemma l4_src_ports_negate_cor:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
      and sports: "(protocol, port) = (l4_src_ports_negate src_ports)"
  shows "match_list (\<beta>, \<alpha>) [MatchNot (Match (Prot (Proto protocol))),  Match (Src_Ports port)] a p \<longleftrightarrow>
           matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports src_ports))) a p"
    apply(subst l4_src_ports_negate[OF generic sports, symmetric])
    by(simp)

  lemma l4_src_ports_negate_helper: (*TODO: deduplicate*)
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
      and sports: "(l4_src_ports_negate src_ports) = (protocol, port)"
  shows
    "matches (\<beta>, \<alpha>) (Match (Src_Ports port)) a p \<or> matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto protocol)))) a p
        \<longleftrightarrow>
     \<not> matches (\<beta>, \<alpha>) (Match (Src_Ports src_ports)) a p"
    apply(cases src_ports, rename_tac proto pts)
    apply(simp)
    apply(insert sports[symmetric])
    apply(simp)
    apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Prot_single_not[OF generic])
    apply(simp add: primitive_matcher_generic.Ports_single[OF generic])
    apply(simp add: raw_ports_invert)
    by blast

  declare l4_src_ports_negate.simps[simp del]

(*\<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> 
 \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> \<And>  \<And> \<And> 
  BIG FAT TODO: optimize away the impossible matches on ports, do intersect on all
  remove the complete match if the protocol match is impossible
  intersection on all port ranges
*)

term Protocols_Normalize.compress_pos_protocols (*can be used on protocol list? or need an or?*)

  (*makes a conjunction over the input. The input is Neg portsA \<and> Neg portsB,
      output is disjunction list. if None, the whole thing cannot match*) (*conjunction of negated protocol list disjunction of ipt_l4_ports*)
  fun l4_src_ports_conjunct_negated
    :: "ipt_l4_ports \<Rightarrow> ipt_l4_ports \<Rightarrow> (primitive_protocol list \<times> ipt_l4_ports list) option" where
    "l4_src_ports_conjunct_negated ps1 ps2 = (
      let (protocol1, ports1) = (l4_src_ports_negate ps1);
          (protocol2, ports2) = (l4_src_ports_negate ps2);
          maybe_ports = l4_src_ports_conjunct ports1 ports2
      in case maybe_ports of None \<Rightarrow> None
                          |  Some ports' \<Rightarrow>
      if
        protocol1 = protocol2
      then
        Some ([protocol1], [ports'])
      else
        Some ([protocol1, protocol2], [ports1, ports2])
      )"

  lemma proto2_is_protocols_helper:
    "[proto2] = protocols \<Longrightarrow> matches (\<beta>, \<alpha>) (alist_and (map (Neg \<circ> Prot \<circ> Proto) protocols)) a p =
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p"
    apply(drule sym)
    by(simp add: bunch_of_lemmata_about_matches)

  lemma proto2proto2_is_protocols_helper: "[proto1, proto2] = protocols \<Longrightarrow> 
    matches (\<beta>, \<alpha>) (alist_and (map (Neg \<circ> Prot \<circ> Proto) protocols)) a p \<longleftrightarrow>
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto1)))) a p \<and>
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p"
    apply(drule sym)
    by(simp add: bunch_of_lemmata_about_matches)

  lemma po1po2_is_ps_helper: "[po1, po2] = ps' \<Longrightarrow> 
    match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) ps') a p \<longleftrightarrow>
    matches (\<beta>, \<alpha>) (Match (Src_Ports po1)) a p \<or> matches (\<beta>, \<alpha>) (Match (Src_Ports po2)) a p"
  apply(drule sym)
  by(simp)

  lemma l4_src_ports_conjunct_negated_Some_obtain:
    assumes "l4_src_ports_conjunct_negated x y = Some ([proto1, proto2], [po1, po2])"
    obtains ps1 ps2 where "po1 = L4Ports proto1 ps1" and "po2 = L4Ports proto2 ps2" and "proto1 \<noteq> proto2"
    using assms apply(simp)
    apply(case_tac "l4_src_ports_negate x")
    apply(case_tac "l4_src_ports_negate y")
    apply(simp split: option.split_asm split_if_asm)
    apply(cases x, cases y)
    apply(simp)
    apply(simp add: l4_src_ports_negate.simps)
    by blast

  lemma ports_proto_ausmultiplizieren_helper:
  assumes generic: "primitive_matcher_generic \<beta>"
  and "proto1 \<noteq> proto2"
  shows
   "((matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto1 ps1))) a p \<or> matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto1)))) a p) \<and>
     (matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto2 ps2))) a p \<or> matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p))
     \<longleftrightarrow>
     (matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto1)))) a p \<and>
      matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p) \<or>
     matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto1 ps1))) a p \<or>
     matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto2 ps2))) a p"
   apply(simp add: primitive_matcher_generic.Ports_single[OF generic]
                   primitive_matcher_generic.Prot_single_not[OF generic])
   using assms(2) by meson
  
  lemma l4_src_ports_conjunct_negated_Some:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "l4_src_ports_conjunct_negated ps1 ps2 = Some (protocols, ps') \<Longrightarrow> 
         (matches (\<beta>, \<alpha>) (alist_and (map (Neg \<circ> Prot \<circ> Proto) protocols)) a p
          \<or>
          match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) ps') a p)
           \<longleftrightarrow>
          (\<not> matches (\<beta>, \<alpha>) (Match (Src_Ports ps1)) a p \<and> \<not> matches (\<beta>, \<alpha>) (Match (Src_Ports ps2)) a p)"
    apply(cases ps1, cases ps2, rename_tac pr1 po1 pr2 po2)
    apply(simp)
    apply(case_tac "l4_src_ports_negate (L4Ports pr1 po1)", simp)
    apply(case_tac "l4_src_ports_negate (L4Ports pr2 po2)", simp)
    apply(rename_tac proto1 po1' proto2 po2')
    apply(simp split: option.split_asm split_if_asm)
     apply(drule l4_src_ports_conjunct_Some[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
     apply(drule l4_src_ports_negate_helper[OF generic, where \<alpha>=\<alpha> and a=a and p=p])+
     apply(subgoal_tac "matches (\<beta>, \<alpha>) (alist_and (map (Neg \<circ> Prot \<circ> Proto) protocols)) a p =
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p")
      apply force
     apply(simp add: proto2_is_protocols_helper; fail)

    (*this case where protocols are not equal seems not to work*)
    apply(drule l4_src_ports_conjunct_Some[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
    apply(drule l4_src_ports_negate_helper[OF generic, where \<alpha>=\<alpha> and a=a and p=p, symmetric])+
    apply(subgoal_tac "matches (\<beta>, \<alpha>) (alist_and (map (Neg \<circ> Prot \<circ> Proto) protocols)) a p \<longleftrightarrow>
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto1)))) a p \<and>
        matches (\<beta>, \<alpha>) (MatchNot (Match (Prot (Proto proto2)))) a p")
     prefer 2
     apply(simp add: proto2proto2_is_protocols_helper; fail)
    apply(simp)
    apply(subst po1po2_is_ps_helper)
     apply blast (*po1' po2'*)
    (*Could work but we need to show that protocol \<and> ports which are unequal protocols are false*)
    apply(case_tac po1', case_tac po2', rename_tac x1 x1' x2 x2')
    apply(simp)
    apply(subgoal_tac "x1=proto1")
     apply(subgoal_tac "x2=proto2")
      apply(simp)
      thm ports_proto_ausmultiplizieren_helper[OF generic, where \<alpha>=\<alpha> and a=a and p=p]
      apply(subst ports_proto_ausmultiplizieren_helper[OF generic, where \<alpha>=\<alpha> and a=a and p=p])
       apply(simp; fail)
      apply(simp; fail)
     apply(simp)
    (*follows from l4_src_ports_conjunct_negated_Some_obtain but needs a better proof style*)
   oops

  (*git commit : this is broken*)

  (*TODO: I want to compress a negataion_type list of ipt_l4_ports*)

  fun l4_src_ports_normalize :: "'i::len itself \<Rightarrow> ipt_l4_ports negation_type list \<Rightarrow> (('i common_primitive) match_expr \<times> ipt_l4_ports list)" where
    "l4_src_ports_normalize _ [] = (MatchAny, [])" |
    "l4_src_ports_normalize meta (Pos (L4Ports proto ps) # ss) = (
        let (aux::'i::len common_primitive match_expr, normalized_primitive) = (MatchNot MatchAny, singletonize_L4Ports proto ps);
        (*TODO: adding the protocol so it can be later-on optimized on protocols and impossible matches are removed. Is this possible?*)
            (aux', normalized_primitive') = l4_src_ports_normalize meta ss
        in (MatchAnd aux aux', normalized_primitive @ normalized_primitive') (*the @ for normalized_primitive is nonesense! they must all match but @ is disjunction here!*)
     )" |
    "l4_src_ports_normalize meta ((Neg p) # ss) = (
        let (aux::'i::len common_primitive match_expr, normalized_primitive) = l4_src_ports_normalize_negate p;
            (aux', normalized_primitive') = l4_src_ports_normalize meta ss
        in (MatchAnd aux aux', normalized_primitive @ normalized_primitive')
     )"


  lemma  assumes generic: "primitive_matcher_generic \<beta>"
   shows "(aux, normalized_primitive) = (l4_src_ports_normalize meta ml) \<Longrightarrow>
            (match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) normalized_primitive) a p \<or> matches (\<beta>, \<alpha>) aux a p \<longleftrightarrow> matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports ml)) a p)"
  proof(induction ml arbitrary: aux normalized_primitive rule: l4_src_ports_normalize.induct)
  print_cases
  case 1 thus ?case by simp
  next
  case (2 meta proto ps ss)
    have IH: "l4_src_ports_normalize meta ss = (aux', normalized_primitive') \<Longrightarrow>
              (match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) normalized_primitive') a p \<or> matches (\<beta>, \<alpha>) aux' a p) =
                matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports ss)) a p" for aux' normalized_primitive'
      by (simp add: "2.IH")
    have Match_Src_Port_pointfree: "(\<lambda>a. Match (Src_Ports a)) = (Match \<circ> Src_Ports)" by fastforce
    from 2(2) show ?case
      apply(simp)
      apply(case_tac "l4_src_ports_normalize meta ss", rename_tac aux' normalized_primitive')
      apply(simp)
      apply(simp add: match_list_append)
      apply(simp add: bunch_of_lemmata_about_matches)
      apply(frule IH[symmetric])
      apply(simp add: Match_Src_Port_pointfree)
      apply(simp add: bunch_of_lemmata_about_matches)
      thm singletonize_L4Ports[OF generic]
      apply(simp add: singletonize_L4Ports[OF generic])
      apply(subgoal_tac "\<not> matches (\<beta>, \<alpha>) aux' a p")
      apply simp
      try0
      thm primitive_matcher_generic.
      apply(simp add: match_list_matches)
    
  next
    (*TODO: why does case 2 not work? ? ?*)
    fix proto ps ss aux normalized_primitive
    let "?case" = "(match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) normalized_primitive) a p \<or> matches (\<beta>, \<alpha>) aux a p) = matches (\<beta>, \<alpha>) (alist_and (NegPos_map C (Pos (L4Ports proto ps) # ss))) a p"
    assume IH : "\<And>x xa y aux normalizedprimitive.
                    x = (Match (Prot (Proto proto)), singletonize_L4Ports proto ps) \<Longrightarrow>
                    (xa, y) = x \<Longrightarrow>
                    (aux, normalized_primitive) = l4_src_ports_normalize ss \<Longrightarrow>
                    (match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) normalized_primitive) a p \<or> matches (\<beta>, \<alpha>) aux a p) = matches (\<beta>, \<alpha>) (alist_and (NegPos_map C ss)) a p"
      and prems : "(aux, normalized_primitive) = l4_src_ports_normalize (Pos (L4Ports proto ps) # ss)"

       sorry
    show ?case
  oops

  lemma  assumes generic: "primitive_matcher_generic \<beta>"
   shows "(match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) (snd (l4_src_ports_normalize ml))) a p \<or> matches (\<beta>, \<alpha>) (fst (l4_src_ports_normalize ml)) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) (alist_and (NegPos_map C ml)) a p)"
  apply(induction ml rule: l4_src_ports_normalize.induct)
    apply(simp; fail)
   apply(simp)
   apply(case_tac "l4_src_ports_normalize ss")
   apply(simp)
   apply(subst singletonize_L4Ports[OF generic])
   thm singletonize_L4Ports[OF generic]





subsection\<open>Normalizing ports\<close>

  (*TODO: new*)
context
begin
(*TODO: probably return just one match expression? rely on nnf normalization later*)
  (*
  fun l4_src_ports_negate_one :: "ipt_l4_ports \<Rightarrow> ('i::len common_primitive) match_expr list" where
    "l4_src_ports_negate_one (L4Ports proto pts) =
          [ MatchNot (Match (Prot (Proto proto))),
            Match (Src_Ports (L4Ports proto (raw_ports_invert pts)))]"
  

  lemma l4_src_ports_negate_one:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "matches (\<beta>, \<alpha>) (MatchNot (Match (Src_Ports src_ports))) a p \<longleftrightarrow> 
         match_list (\<beta>, \<alpha>) (l4_src_ports_negate_one src_ports) a p"
    apply(cases src_ports, rename_tac proto pts)
    apply(simp add: primitive_matcher_generic.Ports_single_not[OF generic])
    apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Prot_single_not[OF generic] primitive_matcher_generic.Ports_single[OF generic])
    by(simp add: raw_ports_invert)

  declare l4_src_ports_negate_one.simps[simp del]*)

(*version two: only one match_expr not normalized returned*)
 
  (*Probably tune as follows:*)
  lemma  assumes generic: "primitive_matcher_generic \<beta>"
   shows "matches (\<beta>, \<alpha>) (andfold_MatchExp (map (Match \<circ> Src_Ports) (singletonize_L4Ports proto pts))) a p \<longleftrightarrow> 
    matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto pts))) a p"
    apply(simp add: singletonize_L4Ports_def)
    apply(induction pts)
     apply(simp add: bunch_of_lemmata_about_matches primitive_matcher_generic.Ports_single[OF generic])
    oops
    (*TODO: yeah, need a big MatchOr or return a list or do the whole thing with normalize_primitive_extract
      probably not using MatchOr but returning a list directly will give better code

     \<And>  \<And> \<And> even better: generalize normalize_primitive_extract that it takes a function which returns a tuple:
      a match expression (here, the match on the protocol) and a common primitive list (the normalized ports)

     does:
      map (MatchAnd rest)  ([first_thing]@(map (\<lambda>port. (Match (Src_Ports port))))

      returns a 'a match_expr list just like normalize_primitive_extract

     call it normalize_primitive_extract_aux (normalize_primitive_extract with an auxilliary match expression)

    bonus: the things are probably all in NNF form and we don't  need to expand MatchOr in code!
      and we can hopefully get rid of the andfold_MatchExp
    *)

end
*)


(*Old stuff from here*)
(*
context
begin

  private fun raw_ports_negation_type_normalize :: "raw_ports negation_type \<Rightarrow> raw_ports" where
    "raw_ports_negation_type_normalize (Pos ps) = ps" |
    "raw_ports_negation_type_normalize (Neg ps) = raw_ports_invert ps"  
  
  
  private lemma "raw_ports_negation_type_normalize (Neg [(0,65535)]) = []" by eval

  declare raw_ports_negation_type_normalize.simps[simp del]
  
  (*
  private lemma raw_ports_negation_type_normalize_correct:
        "primitive_matcher_generic \<beta> \<Longrightarrow> 
         matches (\<beta>, \<alpha>) (negation_type_to_match_expr_f (Src_Ports) ps) a p \<longleftrightarrow>
         matches (\<beta>, \<alpha>) (Match (Src_Ports (raw_ports_negation_type_normalize ps))) a p"
        "primitive_matcher_generic \<beta> \<Longrightarrow> 
         matches (\<beta>, \<alpha>) (negation_type_to_match_expr_f (Dst_Ports) ps) a p \<longleftrightarrow>
         matches (\<beta>, \<alpha>) (Match (Dst_Ports (raw_ports_negation_type_normalize ps))) a p"
  apply(case_tac [!] ps)
  apply(simp_all add: primitive_matcher_generic.Ports_single primitive_matcher_generic.Ports_single_not)
  apply(simp_all add: raw_ports_negation_type_normalize.simps raw_ports_invert split: ternaryvalue.split)
  done
  *)
  




  (* [ [(1,2) \<or> (3,4)]  \<and>  [] ]*)
  text\<open>@{typ "raw_ports list \<Rightarrow> raw_ports"}\<close>
  definition raw_ports_andlist_compress :: "('a::len word \<times> 'a::len word) list list \<Rightarrow> ('a::len word \<times> 'a::len word) list" where
    "raw_ports_andlist_compress pss = wi2l (fold (\<lambda>ps accu. (wordinterval_intersection (l2wi ps) accu)) pss wordinterval_UNIV)"
  
  lemma raw_ports_andlist_compress_correct: "ports_to_set (raw_ports_andlist_compress pss) = \<Inter> set (map ports_to_set pss)"
    proof -
      { fix accu
        have "ports_to_set (wi2l (fold (\<lambda>ps accu. (wordinterval_intersection (l2wi ps) accu)) pss accu)) = (\<Inter> set (map ports_to_set pss)) \<inter> (ports_to_set (wi2l accu))"
          apply(induction pss arbitrary: accu)
           apply(simp_all add: ports_to_set_wordinterval l2wi_wi2l)
          by fast
      }
      from this[of wordinterval_UNIV] show ?thesis
        unfolding raw_ports_andlist_compress_def by(simp add: ports_to_set_wordinterval l2wi_wi2l)
    qed  


  definition raw_ports_compress :: "raw_ports negation_type list \<Rightarrow> raw_ports" where
    "raw_ports_compress pss = raw_ports_andlist_compress (map raw_ports_negation_type_normalize pss)"

  (*
  definition l4_ports_compress :: "ipt_l4_ports negation_type list \<Rightarrow> ipt_l4_ports" where
    "l4_ports_compress pss = raw_ports_andlist_compress (map raw_ports_negation_type_normalize pss)"
  *)
  
  (*only for src*)
  private lemma raw_ports_compress_src_correct:
  fixes p :: "('i::len, 'a) tagged_packet_scheme"
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports ms)) a p \<longleftrightarrow> 
         matches (\<beta>, \<alpha>) (Match (Src_Ports (L4Ports proto (raw_ports_compress ms)))) a p"
  proof(induction ms)
    case Nil with generic show ?case
      unfolding primitive_matcher_generic.Ports_single[OF generic]
      by(simp add: raw_ports_compress_def bunch_of_lemmata_about_matches raw_ports_andlist_compress_correct)
    next
    case (Cons m ms)
      thus ?case
      proof(cases m)
        case Pos thus ?thesis using Cons.IH primitive_matcher_generic.Ports_single[OF generic]
          by(simp add: raw_ports_compress_def raw_ports_andlist_compress_correct bunch_of_lemmata_about_matches
                raw_ports_negation_type_normalize.simps)
        next
        case (Neg a)
          thus ?thesis using Cons.IH generic primitive_matcher_generic.Ports_single_not[where p = p] primitive_matcher_generic.Ports_single[where p = p]
          apply(simp add: raw_ports_compress_def raw_ports_andlist_compress_correct
                          bunch_of_lemmata_about_matches[where p = p])
          apply(simp add: raw_ports_invert raw_ports_negation_type_normalize.simps)
          done
        qed
  qed
  (*only for dst*)
  private lemma raw_ports_compress_dst_correct:
  assumes generic: "primitive_matcher_generic \<beta>"
  shows "matches (\<beta>, \<alpha>) (alist_and (NegPos_map Dst_Ports ms)) a p \<longleftrightarrow>
         matches (\<beta>, \<alpha>) (Match (Dst_Ports (raw_ports_compress ms))) a p"
  proof(induction ms)
    case Nil thus ?case
      unfolding primitive_matcher_generic.Ports_single[OF generic]
      by(simp add: raw_ports_compress_def bunch_of_lemmata_about_matches raw_ports_andlist_compress_correct)
    next
    case (Cons m ms)
      thus ?case
      proof(cases m)
        case Pos thus ?thesis using Cons.IH primitive_matcher_generic.Ports_single[OF generic]
          by(simp add: raw_ports_compress_def raw_ports_andlist_compress_correct bunch_of_lemmata_about_matches
                raw_ports_negation_type_normalize.simps)
        next
        case (Neg a)
          thus ?thesis using Cons.IH primitive_matcher_generic.Ports_single[OF generic] primitive_matcher_generic.Ports_single_not[OF generic]
          apply(simp add: raw_ports_compress_def raw_ports_andlist_compress_correct
                          bunch_of_lemmata_about_matches)
          apply(simp add: raw_ports_invert raw_ports_negation_type_normalize.simps)
          done
        qed
  qed
  
  (*
  private lemma raw_ports_compress_matches_set: "primitive_matcher_generic \<beta> \<Longrightarrow>
         matches (\<beta>, \<alpha>) (Match (Src_Ports (raw_ports_compress ips))) a p \<longleftrightarrow>
         p_sport p \<in> \<Inter> set (map (ports_to_set \<circ> raw_ports_negation_type_normalize) ips)"
  apply(simp add: raw_ports_compress_def)
  apply(induction ips)
   apply(simp)
   apply(simp add: raw_ports_compress_def bunch_of_lemmata_about_matches
                   raw_ports_andlist_compress_correct primitive_matcher_generic_def; fail)
  apply(rename_tac m ms)
  apply(case_tac m)
   apply(simp add: primitive_matcher_generic.Ports_single raw_ports_andlist_compress_correct; fail)
  apply(simp add: primitive_matcher_generic.Ports_single raw_ports_andlist_compress_correct; fail)
  done
  *)
  (*
  (*spliting the primitives: multiport list (a list of disjunction!)*)
  private lemma singletonize_SrcDst_Ports:
      "(*primitive_matcher_generic \<beta> \<Longrightarrow>  multiports_disjuction TODO *)
       match_list (common_matcher, \<alpha>) (map (\<lambda>spt. (MatchAnd (Match (Src_Ports [spt]))) ms) (spts)) a p \<longleftrightarrow>
       matches (common_matcher, \<alpha>) (MatchAnd (Match (Src_Ports spts)) ms) a p"
      "match_list (common_matcher, \<alpha>) (map (\<lambda>spt. (MatchAnd (Match (Dst_Ports [spt]))) ms) (dpts)) a p \<longleftrightarrow>
       matches (common_matcher, \<alpha>) (MatchAnd (Match (Dst_Ports dpts)) ms) a p"
    apply(simp_all add: match_list_matches bunch_of_lemmata_about_matches(1) multiports_disjuction)
  done
  *)
  
  
  (*idea:*)
  value "case primitive_extractor (is_Src_Ports, src_ports_sel) m 
          of (spts, rst) \<Rightarrow> map (\<lambda>spt. (MatchAnd (Match ((Src_Ports [spt]) :: 32 common_primitive))) rst) (raw_ports_compress spts)"
  
  
  text\<open>Normalizing match expressions such that at most one port will exist in it. Returns a list of match expressions (splits one firewall rule into several rules).\<close>
  definition normalize_ports_step :: "(('i::len common_primitive \<Rightarrow> bool) \<times> ('i common_primitive \<Rightarrow> raw_ports)) \<Rightarrow> 
                               (raw_ports \<Rightarrow> 'i common_primitive) \<Rightarrow>
                               'i common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where 
    "normalize_ports_step (disc_sel) C = normalize_primitive_extract disc_sel C (\<lambda>me. map (\<lambda>pt. [pt]) (raw_ports_compress me))"

  definition normalize_src_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_src_ports = normalize_ports_step (is_Src_Ports, src_ports_sel) Src_Ports"  
  definition normalize_dst_ports :: "'i::len common_primitive match_expr \<Rightarrow> 'i common_primitive match_expr list" where
    "normalize_dst_ports = normalize_ports_step (is_Dst_Ports, dst_ports_sel) Dst_Ports"

  lemma normalize_src_ports: assumes generic: "primitive_matcher_generic \<beta>" and n: "normalized_nnf_match m" shows
        "match_list (\<beta>, \<alpha>) (normalize_src_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
    proof -
      { fix ml
        have "match_list (\<beta>, \<alpha>) (map (Match \<circ> Src_Ports) (map (\<lambda>pt. [pt]) (raw_ports_compress ml))) a p =
         matches (\<beta>, \<alpha>) (alist_and (NegPos_map Src_Ports ml)) a p"
         using raw_ports_compress_src_correct[OF generic] primitive_matcher_generic.multiports_disjuction[OF generic]
         by(simp add: match_list_matches)
      } with normalize_primitive_extract[OF n wf_disc_sel_common_primitive(1), where \<gamma>="(\<beta>, \<alpha>)"]
      show ?thesis
        unfolding normalize_src_ports_def normalize_ports_step_def by simp
    qed

    lemma normalize_dst_ports: assumes generic: "primitive_matcher_generic \<beta>" and n: "normalized_nnf_match m" shows
        "match_list (\<beta>, \<alpha>) (normalize_dst_ports m) a p \<longleftrightarrow> matches (\<beta>, \<alpha>) m a p"
    proof -
      { fix ml
        have "match_list (\<beta>, \<alpha>) (map (Match \<circ> Dst_Ports) (map (\<lambda>pt. [pt]) (raw_ports_compress ml))) a p =
         matches (\<beta>, \<alpha>) (alist_and (NegPos_map Dst_Ports ml)) a p"
         using raw_ports_compress_dst_correct[OF generic] primitive_matcher_generic.multiports_disjuction[OF generic]
         by(simp add: match_list_matches)
      } with normalize_primitive_extract[OF n wf_disc_sel_common_primitive(2), where \<gamma>="(\<beta>, \<alpha>)"]
      show ?thesis
        unfolding normalize_dst_ports_def normalize_ports_step_def by simp
    qed


  value "normalized_nnf_match (MatchAnd (MatchNot (Match (Src_Ports [(1,2)]))) (Match (Src_Ports [(1,2)])))"
  value "normalize_src_ports (MatchAnd (MatchNot (Match (Src_Ports [(5,9)]))) (Match (Src_Ports [(1,2)])))"

  (*probably we should optimize away the (Match (Src_Ports [(0, 65535)]))*)
  value "normalize_src_ports (MatchAnd (MatchNot (Match (Prot (Proto TCP)))) (Match (Prot (ProtoAny))))"
  
  fun normalized_src_ports :: "'i::len common_primitive match_expr \<Rightarrow> bool" where
    "normalized_src_ports MatchAny = True" |
    "normalized_src_ports (Match (Src_Ports [])) = True" |
    "normalized_src_ports (Match (Src_Ports [_])) = True" |
    "normalized_src_ports (Match (Src_Ports _)) = False" |
    "normalized_src_ports (Match _) = True" |
    "normalized_src_ports (MatchNot (Match (Src_Ports _))) = False" |
    "normalized_src_ports (MatchNot (Match _)) = True" |
    "normalized_src_ports (MatchAnd m1 m2) = (normalized_src_ports m1 \<and> normalized_src_ports m2)" |
    "normalized_src_ports (MatchNot (MatchAnd _ _)) = False" |
    "normalized_src_ports (MatchNot (MatchNot _)) = False" |
    "normalized_src_ports (MatchNot MatchAny) = True"
  
  fun normalized_dst_ports :: "'i::len common_primitive match_expr \<Rightarrow> bool" where
    "normalized_dst_ports MatchAny = True" |
    "normalized_dst_ports (Match (Dst_Ports [])) = True" |
    "normalized_dst_ports (Match (Dst_Ports [_])) = True" |
    "normalized_dst_ports (Match (Dst_Ports _)) = False" |
    "normalized_dst_ports (Match _) = True" |
    "normalized_dst_ports (MatchNot (Match (Dst_Ports _))) = False" |
    "normalized_dst_ports (MatchNot (Match _)) = True" |
    "normalized_dst_ports (MatchAnd m1 m2) = (normalized_dst_ports m1 \<and> normalized_dst_ports m2)" |
    "normalized_dst_ports (MatchNot (MatchAnd _ _)) = False" |
    "normalized_dst_ports (MatchNot (MatchNot _)) = False" |
    "normalized_dst_ports (MatchNot MatchAny) = True" 

  lemma normalized_src_ports_def2: "normalized_src_ports ms = normalized_n_primitive (is_Src_Ports, src_ports_sel) (\<lambda>pts. length pts \<le> 1) ms"
    by(induction ms rule: normalized_src_ports.induct, simp_all)
  lemma normalized_dst_ports_def2: "normalized_dst_ports ms = normalized_n_primitive (is_Dst_Ports, dst_ports_sel) (\<lambda>pts. length pts \<le> 1) ms"
    by(induction ms rule: normalized_dst_ports.induct, simp_all)
  
  
  private lemma "\<forall>spt \<in> set (raw_ports_compress spts). normalized_src_ports (Match (Src_Ports [spt]))" by(simp)
  

  lemma normalize_src_ports_normalized_n_primitive: "normalized_nnf_match m \<Longrightarrow> 
      \<forall>m' \<in> set (normalize_src_ports m). normalized_src_ports m'"
  unfolding normalize_src_ports_def normalize_ports_step_def
  unfolding normalized_src_ports_def2
  apply(rule normalize_primitive_extract_normalizes_n_primitive[OF _ wf_disc_sel_common_primitive(1)])
   by(simp_all)


  lemma "normalized_nnf_match m \<Longrightarrow>
      \<forall>m' \<in> set (normalize_src_ports m). normalized_src_ports m' \<and> normalized_nnf_match m'"
  apply(intro ballI, rename_tac mn)
  apply(rule conjI)
   apply(simp add: normalize_src_ports_normalized_n_primitive)
  unfolding normalize_src_ports_def normalize_ports_step_def
  unfolding normalized_dst_ports_def2
   by(auto dest: normalize_primitive_extract_preserves_nnf_normalized[OF _ wf_disc_sel_common_primitive(1)])

  lemma normalize_dst_ports_normalized_n_primitive: "normalized_nnf_match m \<Longrightarrow> 
      \<forall>m' \<in> set (normalize_dst_ports m). normalized_dst_ports m'"
  unfolding normalize_dst_ports_def normalize_ports_step_def
  unfolding normalized_dst_ports_def2
  apply(rule normalize_primitive_extract_normalizes_n_primitive[OF _ wf_disc_sel_common_primitive(2)])
   by(simp_all)

  (*using the generalized version, we can push through normalized conditions*)
  lemma "normalized_nnf_match m \<Longrightarrow> normalized_dst_ports m \<Longrightarrow>
    \<forall>mn \<in> set (normalize_src_ports m). normalized_dst_ports mn"
  unfolding normalized_dst_ports_def2 normalize_src_ports_def normalize_ports_step_def
  apply(frule(1) normalize_primitive_extract_preserves_unrelated_normalized_n_primitive[OF _ _ wf_disc_sel_common_primitive(1), where f="(\<lambda>me. map (\<lambda>pt. [pt]) (raw_ports_compress me))"])
   apply(simp_all)
  done

end*)
*)
end
